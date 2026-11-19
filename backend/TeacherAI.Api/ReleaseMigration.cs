using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace TeacherAI.Api;

internal static class ReleaseMigration
{
    public static async Task Run(ClassroomDb db, string password)
    {
        if (string.IsNullOrWhiteSpace(password)) throw new InvalidOperationException("Set the API database password.");
        await db.Database.MigrateAsync();
        // Use a transaction-local setting to bind the secret as data. The API role
        // receives only the table privileges needed for normal classroom requests.
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await db.Database.OpenConnectionAsync();
        await using var transaction = await connection.BeginTransactionAsync();
        await using var command = new NpgsqlCommand("""
            SELECT pg_advisory_xact_lock(8421706431);
            SELECT set_config('teacher.api_password', @password, true);
            DO $setup$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'teacher_api') THEN
                    CREATE ROLE teacher_api LOGIN;
                END IF;
                EXECUTE format('ALTER ROLE teacher_api PASSWORD %L', current_setting('teacher.api_password'));
            END
            $setup$;
            GRANT USAGE ON SCHEMA public TO teacher_api;
            GRANT SELECT, INSERT, UPDATE, DELETE ON "Records", "Receipts", "DeletedAccounts" TO teacher_api;
            """, connection, transaction);
        command.Parameters.AddWithValue("password", password);
        await command.ExecuteNonQueryAsync();
        await transaction.CommitAsync();
    }
}
