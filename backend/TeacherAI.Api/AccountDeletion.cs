using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace TeacherAI.Api;

public static class AccountDeletion
{
    static string Hash(string owner) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(owner)));

    public static Task<bool> IsDeleted(ClassroomDb db, string owner, CancellationToken ct) =>
        db.DeletedAccounts.AnyAsync(a => a.SubjectHash == Hash(owner), ct);

    public static IResult Gone(string owner) => Results.Json(new { account = owner }, statusCode: 410);

    public static async Task<IResult> Request(ClaimsPrincipal user, ClassroomDb db, Auth0Accounts accounts,
        CancellationToken ct)
    {
        if (!accounts.Configured) return Results.StatusCode(503);
        var owner = user.FindFirstValue("sub")!;
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({owner}, 0))", ct);
        if (!await IsDeleted(db, owner, ct))
        {
            db.DeletedAccounts.Add(new() { SubjectHash = Hash(owner), PendingSubject = owner, RequestedUtc = DateTime.UtcNow });
            await db.Records.Where(r => r.Owner == owner).ExecuteDeleteAsync(ct);
            await db.Receipts.Where(r => r.Owner == owner).ExecuteDeleteAsync(ct);
            await db.SaveChangesAsync(ct);
        }
        await tx.CommitAsync(ct);
        return Results.Accepted();
    }
}

public sealed class Auth0Accounts(IHttpClientFactory clients, IConfiguration configuration)
{
    readonly IConfigurationSection settings = configuration.GetSection("Identity");
    public bool Configured => !string.IsNullOrWhiteSpace(settings["ManagementClientId"]) &&
        !string.IsNullOrWhiteSpace(settings["ManagementClientSecret"]);

    public async Task Delete(string subject, CancellationToken ct)
    {
        var issuer = new Uri(settings["Authority"]!);
        if (issuer.Scheme != Uri.UriSchemeHttps) throw new InvalidOperationException("Auth0 requires HTTPS.");
        using var client = clients.CreateClient("identity-management");
        using var token = await client.PostAsJsonAsync(new Uri(issuer, "/oauth/token"), new
        {
            grant_type = "client_credentials", client_id = settings["ManagementClientId"],
            client_secret = settings["ManagementClientSecret"], audience = new Uri(issuer, "/api/v2/").AbsoluteUri
        }, ct);
        token.EnsureSuccessStatusCode();
        var json = await token.Content.ReadFromJsonAsync<JsonElement>(ct);
        using var request = new HttpRequestMessage(HttpMethod.Delete,
            new Uri(issuer, "/api/v2/users/" + Uri.EscapeDataString(subject)));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", json.GetProperty("access_token").GetString());
        using var response = await client.SendAsync(request, ct);
        if (response.StatusCode != HttpStatusCode.NotFound) response.EnsureSuccessStatusCode();
    }
}

public sealed class AccountDeletionWorker(IServiceScopeFactory scopes, ILogger<AccountDeletionWorker> logger)
    : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(30));
        do
        {
            try
            {
                using var scope = scopes.CreateScope();
                var accounts = scope.ServiceProvider.GetRequiredService<Auth0Accounts>();
                if (!accounts.Configured) continue;
                var db = scope.ServiceProvider.GetRequiredService<ClassroomDb>();
                var pending = await db.DeletedAccounts.Where(a => a.PendingSubject != null)
                    .OrderBy(a => a.RequestedUtc).ToListAsync(ct);
                foreach (var row in pending)
                {
                    try
                    {
                        await accounts.Delete(row.PendingSubject!, ct);
                        row.PendingSubject = null;
                        await db.SaveChangesAsync(ct);
                    }
                    catch (Exception) when (!ct.IsCancellationRequested)
                    {
                        logger.LogError("Identity removal failed and remains queued.");
                    }
                }
            }
            catch (Exception) when (!ct.IsCancellationRequested)
            {
                logger.LogError("Could not process the account deletion queue.");
            }
        } while (await timer.WaitForNextTickAsync(ct));
    }
}
