using Microsoft.EntityFrameworkCore;

namespace TeacherAI.Api;

public sealed class ClassroomDb(DbContextOptions<ClassroomDb> options) : DbContext(options)
{
    public DbSet<WorkspaceRecord> Records => Set<WorkspaceRecord>();
    public DbSet<Receipt> Receipts => Set<Receipt>();
    public DbSet<DeletedAccount> DeletedAccounts => Set<DeletedAccount>();
    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<WorkspaceRecord>().HasKey(r => new { r.Owner, r.Key });
        model.Entity<WorkspaceRecord>().HasIndex(r => new { r.Owner, r.Cursor });
        model.Entity<DeletedAccount>().HasKey(r => r.SubjectHash);
        model.Entity<Receipt>().HasKey(r => new { r.Owner, r.OperationId });
    }
}

public sealed class WorkspaceRecord
{
    public required string Owner { get; init; }
    public required string Key { get; init; }
    public string? Payload { get; set; }
    public long Revision { get; set; }
    public long Cursor { get; set; }
}

public sealed class Receipt
{
    public required string Owner { get; init; }
    public Guid OperationId { get; init; }
    public long Cursor { get; init; }
    public required string Digest { get; init; }
}

public sealed class DeletedAccount
{
    public required string SubjectHash { get; init; }
    public string? PendingSubject { get; set; }
    public DateTime RequestedUtc { get; init; }
}
