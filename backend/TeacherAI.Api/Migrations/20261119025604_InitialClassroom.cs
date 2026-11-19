using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TeacherAI.Api.Migrations
{
    /// <inheritdoc />
    public partial class InitialClassroom : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Receipts",
                columns: table => new
                {
                    Owner = table.Column<string>(type: "text", nullable: false),
                    OperationId = table.Column<Guid>(type: "uuid", nullable: false),
                    Cursor = table.Column<long>(type: "bigint", nullable: false),
                    Digest = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Receipts", x => new { x.Owner, x.OperationId });
                });

            migrationBuilder.CreateTable(
                name: "Records",
                columns: table => new
                {
                    Owner = table.Column<string>(type: "text", nullable: false),
                    Key = table.Column<string>(type: "text", nullable: false),
                    Payload = table.Column<string>(type: "text", nullable: true),
                    Revision = table.Column<long>(type: "bigint", nullable: false),
                    Cursor = table.Column<long>(type: "bigint", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Records", x => new { x.Owner, x.Key });
                });

            migrationBuilder.CreateIndex(
                name: "IX_Records_Owner_Cursor",
                table: "Records",
                columns: new[] { "Owner", "Cursor" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Receipts");

            migrationBuilder.DropTable(
                name: "Records");
        }
    }
}
