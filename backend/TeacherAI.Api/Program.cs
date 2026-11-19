using System.Security.Claims;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.EntityFrameworkCore;
using TeacherAI.Api;

var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();
builder.Services.AddOpenApi();
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = 429;
    options.AddPolicy("classroom", context => RateLimitPartition.GetFixedWindowLimiter(
        context.User.FindFirstValue("sub") ?? "anonymous", _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 180, Window = TimeSpan.FromMinutes(1)
        }));
});
builder.Services.AddDbContext<ClassroomDb>(o => o.UseNpgsql(
    builder.Configuration.GetConnectionString("classroom")));
if (args.Contains("--migrate-only", StringComparer.Ordinal))
{
    await using var migrationApp = builder.Build();
    await using var scope = migrationApp.Services.CreateAsyncScope();
    await ReleaseMigration.Run(scope.ServiceProvider.GetRequiredService<ClassroomDb>(),
        builder.Configuration["Database:ApiPassword"] ?? "");
    return;
}
var identity = builder.Configuration.GetRequiredSection("Identity");
var origin = new Uri(identity["PublicOrigin"]!);
if (origin.Scheme != "https" || origin.AbsolutePath != "/")
    throw new InvalidOperationException("Configure an HTTPS public origin.");
builder.Services.AddAuthentication("session")
    .AddPolicyScheme("session", null, options => options.ForwardDefaultSelector = c =>
        c.Request.Headers.ContainsKey("Authorization") ? "Bearer" : "Cookies")
    .AddCookie(options =>
    {
        options.Cookie.Name = "__Host-teacher";
        options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
        options.Events.OnRedirectToAccessDenied = c => { c.Response.StatusCode = 403; return Task.CompletedTask; };
        options.Events.OnRedirectToLogin = c => { c.Response.StatusCode = 401; return Task.CompletedTask; };
    })
    .AddJwtBearer(options =>
    {
        options.MapInboundClaims = false;
        options.Authority = identity["Authority"];
        options.Audience = identity["Audience"];
    })
    .AddOpenIdConnect("oidc", options =>
    {
        options.SignInScheme = CookieAuthenticationDefaults.AuthenticationScheme;
        options.Authority = identity["Authority"];
        options.ClientId = identity["ClientId"];
        options.ClientSecret = identity["ClientSecret"];
        options.ResponseType = "code";
        options.Prompt = "login";
        options.MapInboundClaims = false;
        options.Events.OnRedirectToIdentityProvider = c =>
        {
            c.ProtocolMessage.RedirectUri = new Uri(origin, "/signin-oidc").AbsoluteUri;
            return Task.CompletedTask;
        };
        options.Events.OnAuthorizationCodeReceived = c =>
        {
            c.TokenEndpointRequest!.RedirectUri = new Uri(origin, "/signin-oidc").AbsoluteUri;
            return Task.CompletedTask;
        };
    });
builder.Services.AddHttpClient("identity-management").RemoveAllLoggers()
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
builder.Services.AddSingleton<Auth0Accounts>();
builder.Services.AddHostedService<AccountDeletionWorker>();
builder.Services.AddAuthorization();
builder.Services.AddAntiforgery(o =>
{
    o.HeaderName = "X-CSRF";
    o.Cookie.SecurePolicy = CookieSecurePolicy.Always;
});
var app = builder.Build();
if (builder.Configuration.GetValue("Database:ApplyMigrations", true))
{
    await using var scope = app.Services.CreateAsyncScope();
    await scope.ServiceProvider.GetRequiredService<ClassroomDb>().Database.MigrateAsync();
}
app.UseDefaultFiles();
app.UseStaticFiles(new StaticFileOptions { ServeUnknownFileTypes = true });
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
app.MapGet("/ready", async (HttpContext http, ClassroomDb db, CancellationToken ct) =>
{
    http.Response.Headers.CacheControl = "no-store";
    return await db.Database.CanConnectAsync(ct) ? Results.NoContent() : Results.StatusCode(503);
});
app.MapDefaultEndpoints();
if (app.Environment.IsDevelopment()) app.MapOpenApi();
app.MapGet("/auth/login", () => Results.Challenge(new AuthenticationProperties { RedirectUri = "/" }, ["oidc"]));
var generation = app.Configuration["Database:Generation"] ?? "classroom";
var api = app.MapGroup("/api/v1").RequireAuthorization().RequireRateLimiting("classroom");
api.AddEndpointFilter(async (context, next) =>
{
    var http = context.HttpContext;
    http.Response.Headers.CacheControl = "no-store";
    if (http.Request.Path == "/api/v1/mutations" || http.Request.Path == "/api/v1/changes")
    {
        http.Response.OnCompleted(() =>
        {
            var status = http.Response.StatusCode;
            if (status >= 500 || status == 400 || status == 422)
                app.Logger.LogWarning("Classroom sync failed with HTTP {StatusCode}", status);
            return Task.CompletedTask;
        });
    }
    var owner = http.User.FindFirstValue("sub");
    if (string.IsNullOrEmpty(owner)) return Results.Unauthorized();
    if (http.Request.Path != "/api/v1/session" &&
        http.Request.Headers["X-Workspace-Account"] != owner) return Results.Forbid();
    if (!HttpMethods.IsGet(http.Request.Method) && !http.Request.Headers.ContainsKey("Authorization") &&
        !await http.RequestServices.GetRequiredService<IAntiforgery>().IsRequestValidAsync(http))
        return Results.BadRequest();
    if (http.Request.Path != "/api/v1/logout" && !HttpMethods.IsDelete(http.Request.Method) &&
        await AccountDeletion.IsDeleted(http.RequestServices.GetRequiredService<ClassroomDb>(), owner, http.RequestAborted))
        return AccountDeletion.Gone(owner);
    if ((http.Request.Path == "/api/v1/workspace" || http.Request.Path == "/api/v1/changes" ||
         http.Request.Path == "/api/v1/mutations") &&
        (http.Request.Headers["X-Classroom-Generation"].FirstOrDefault() ?? "classroom") != generation)
        return Results.StatusCode(412);
    return await next(context);
});
api.MapDelete("/account", AccountDeletion.Request);
api.MapGet("/session", (HttpContext c, IAntiforgery antiforgery) => new
{
    account = c.User.FindFirstValue("sub"),
    generation,
    csrf = c.Request.Headers.ContainsKey("Authorization") ? null : antiforgery.GetAndStoreTokens(c).RequestToken
});
api.MapPost("/logout", async (HttpContext c) =>
{
    await c.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
    return Results.NoContent();
});
api.MapGet("/workspace", (ClassroomDb db, ClaimsPrincipal user, CancellationToken ct) =>
    Sync.Read(db, user.FindFirstValue("sub")!, 0, ct));
api.MapGet("/changes", (long after, ClassroomDb db, ClaimsPrincipal user, CancellationToken ct) =>
    Sync.Read(db, user.FindFirstValue("sub")!, after, ct));
api.MapPost("/mutations", Sync.Apply);
app.MapFallbackToFile("index.html");
app.Run();

public partial class Program;
