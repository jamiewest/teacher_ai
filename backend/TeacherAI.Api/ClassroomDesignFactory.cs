using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace TeacherAI.Api;

public sealed class ClassroomDesignFactory : IDesignTimeDbContextFactory<ClassroomDb>
{
    public ClassroomDb CreateDbContext(string[] args) => new(
        new DbContextOptionsBuilder<ClassroomDb>().UseNpgsql().Options);
}
