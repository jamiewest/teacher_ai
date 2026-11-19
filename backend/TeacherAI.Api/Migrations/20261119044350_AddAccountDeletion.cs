using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TeacherAI.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddAccountDeletion : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "DeletedAccounts",
                columns: table => new
                {
                    SubjectHash = table.Column<string>(type: "text", nullable: false),
                    PendingSubject = table.Column<string>(type: "text", nullable: true),
                    RequestedUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DeletedAccounts", x => x.SubjectHash);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "DeletedAccounts");
        }
    }
}
