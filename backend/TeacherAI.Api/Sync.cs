using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace TeacherAI.Api;

public sealed record Edit(string Key, long Revision, JsonElement? Value);
public sealed record Mutation(Guid OperationId, Edit[] Edits);
public sealed record Change(string Key, long Revision, JsonElement? Value);
public sealed record Changes(long Cursor, Change[] Records);

public static class Sync
{
    private static readonly HashSet<string> Collections =
        ["subjects", "students", "tags", "classes", "layouts", "assignments", "periods", "participation"];

    public static async Task<Changes> Read(ClassroomDb db, string owner, long after, CancellationToken ct)
    {
        var rows = await db.Records.AsNoTracking().Where(r => r.Owner == owner && r.Cursor > after)
            .OrderBy(r => r.Cursor).ThenBy(r => r.Key).ToArrayAsync(ct);
        return new(rows.LastOrDefault()?.Cursor ?? after,
            rows.Select(r => new Change(r.Key, r.Revision,
                r.Payload is null ? null : JsonSerializer.Deserialize<JsonElement>(r.Payload))).ToArray());
    }

    public static async Task<IResult> Apply(Mutation batch, ClaimsPrincipal user, ClassroomDb db, CancellationToken ct)
    {
        if (batch.OperationId == Guid.Empty || batch.Edits is not { Length: > 0 } ||
            batch.Edits.Any(e => e is null || !Valid(e)) ||
            batch.Edits.Select(e => e.Key).Distinct().Count() != batch.Edits.Length)
            return Results.BadRequest();
        var owner = user.FindFirstValue("sub")!;
        var digest = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(batch)));
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        // Serialize only this teacher's writes, including first insert and lost-response retries.
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({owner}, 0))", ct);
        if (await AccountDeletion.IsDeleted(db, owner, ct)) return AccountDeletion.Gone(owner);
        var receipt = await db.Receipts.FindAsync([owner, batch.OperationId], ct);
        if (receipt is not null)
            return digest == receipt.Digest ? Results.Ok(new { receipt.Cursor }) : Results.BadRequest();
        var keys = batch.Edits.Select(e => e.Key).ToArray();
        var rows = await db.Records.Where(r => r.Owner == owner && keys.Contains(r.Key))
            .ToDictionaryAsync(r => r.Key, ct);
        var conflicts = batch.Edits.Where(e => (rows.GetValueOrDefault(e.Key)?.Revision ?? 0) != e.Revision)
            .Select(e => e.Key).ToArray();
        if (conflicts.Length > 0) return Results.Conflict(new { conflicts });
        var rosterError = await ValidateRoster(db, owner, batch.Edits, ct);
        if (rosterError is not null) return Results.UnprocessableEntity(new { message = rosterError });
        var cursor = (await db.Records.Where(r => r.Owner == owner).MaxAsync(r => (long?)r.Cursor, ct) ?? 0) + 1;
        foreach (var edit in batch.Edits)
        {
            if (!rows.TryGetValue(edit.Key, out var row))
            {
                row = new WorkspaceRecord { Owner = owner, Key = edit.Key };
                db.Records.Add(row);
            }
            row.Payload = edit.Value?.GetRawText();
            row.Revision++;
            row.Cursor = cursor;
        }
        db.Receipts.Add(new Receipt { Owner = owner, OperationId = batch.OperationId, Digest = digest, Cursor = cursor });
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return Results.Ok(new { cursor });
    }

    private static async Task<string?> ValidateRoster(ClassroomDb db, string owner, Edit[] edits, CancellationToken ct)
    {
        bool IsRosterKey(string key) => key.StartsWith("students/") || key.StartsWith("classes/") || key.StartsWith("tags/");
        if (!edits.Any(e => IsRosterKey(e.Key))) return null;
        var stored = await db.Records.AsNoTracking().Where(r => r.Owner == owner && r.Payload != null &&
            (r.Key.StartsWith("students/") || r.Key.StartsWith("classes/") || r.Key.StartsWith("tags/")))
            .Select(r => new { r.Key, r.Payload }).ToArrayAsync(ct);
        var roster = stored.ToDictionary(r => r.Key, r => JsonSerializer.Deserialize<JsonElement>(r.Payload!));
        foreach (var edit in edits.Where(e => IsRosterKey(e.Key)))
        {
            if (edit.Value is {} value) roster[edit.Key] = value;
            else roster.Remove(edit.Key);
        }
        foreach (var (key, record) in roster)
        {
            var (field, prefix) = key.StartsWith("classes/") ? ("studentIds", "students/") : ("tagIds", "tags/");
            if (!record.TryGetProperty(field, out var ids)) continue;
            if (ids.ValueKind != JsonValueKind.Array || ids.EnumerateArray().Any(id =>
                    id.ValueKind != JsonValueKind.String || !roster.ContainsKey(prefix + id.GetString())))
                return "A roster membership or tag refers to a missing record. Review the roster and sync again.";
        }
        return null;
    }

    private static bool Valid(Edit edit)
    {
        if (string.IsNullOrEmpty(edit.Key) || edit.Key.Length > 180 || edit.Revision < 0) return false;
        if (edit.Key == "calendar") return edit.Value is { ValueKind: JsonValueKind.Object };
        var parts = edit.Key.Split('/');
        if (parts.Length != 2 || !Collections.Contains(parts[0]) || parts[1].Length == 0) return false;
        return edit.Value is null || (edit.Value is { ValueKind: JsonValueKind.Object } value &&
            value.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.String && id.GetString() == parts[1]);
    }
}
