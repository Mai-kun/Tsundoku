using System.Net;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Serilog;

namespace MediaTracker.Server.Infrastructure.Security;

public sealed class ApiKeyAuthMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        // Allow CORS preflight requests
        if (HttpMethods.IsOptions(context.Request.Method))
        {
            await next(context);
            return;
        }

        var path = context.Request.Path.Value ?? string.Empty;

        // Static files, OpenAPI schema and documentation UI are publicly accessible
        if (!path.StartsWith("/api/", StringComparison.OrdinalIgnoreCase)
            || path.StartsWith("/api/docs", StringComparison.OrdinalIgnoreCase)
            || path.StartsWith("/openapi", StringComparison.OrdinalIgnoreCase))
        {
            await next(context);
            return;
        }

        var authHeader = context.Request.Headers.Authorization.ToString();
        var apiKeyHeader = context.Request.Headers["X-Api-Key"].ToString();
        var hasAuthHeader = !string.IsNullOrWhiteSpace(authHeader) || !string.IsNullOrWhiteSpace(apiKeyHeader);
        var isLoopback = IsLoopbackAddress(context.Connection.RemoteIpAddress);

        // Local loopback access without explicit token headers is trusted (frictionless UI mode)
        if (isLoopback && !hasAuthHeader)
        {
            await next(context);
            return;
        }

        // Remote request or explicit token header provided: authenticate token
        string? token = null;
        if (!string.IsNullOrWhiteSpace(authHeader))
        {
            const string bearerPrefix = "Bearer ";
            token = authHeader.StartsWith(bearerPrefix, StringComparison.OrdinalIgnoreCase)
                ? authHeader[bearerPrefix.Length..].Trim()
                : authHeader.Trim();
        }
        else if (!string.IsNullOrWhiteSpace(apiKeyHeader))
        {
            token = apiKeyHeader.Trim();
        }

        if (string.IsNullOrEmpty(token))
        {
            await ReturnUnauthorizedAsync(context, "API token is required for remote access");
            return;
        }

        var tokenHash = ApiTokenHelper.ComputeHash(token);
        var db = context.RequestServices.GetRequiredService<AppDbContext>();

        var apiToken = await db.ApiTokens
            .AsNoTracking()
            .FirstOrDefaultAsync(t => t.TokenHash == tokenHash && (t.ExpiresAt == null || t.ExpiresAt > DateTime.UtcNow));

        if (apiToken is null)
        {
            await ReturnUnauthorizedAsync(context, "Invalid or expired API token");
            return;
        }

        // Update LastUsedAt in background if more than 1 minute has elapsed
        if (!apiToken.LastUsedAt.HasValue || (DateTime.UtcNow - apiToken.LastUsedAt.Value) > TimeSpan.FromMinutes(1))
        {
            var scopeFactory = context.RequestServices.GetRequiredService<IServiceScopeFactory>();
            var tokenId = apiToken.Id;
            _ = Task.Run(async () =>
            {
                try
                {
                    using var scope = scopeFactory.CreateScope();
                    var scopeDb = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                    await scopeDb.ApiTokens
                        .Where(t => t.Id == tokenId)
                        .ExecuteUpdateAsync(s => s.SetProperty(t => t.LastUsedAt, DateTime.UtcNow));
                }
                catch (Exception ex)
                {
                    Log.Warning(ex, "Failed to update LastUsedAt for API token {TokenId}", tokenId);
                }
            });
        }

        await next(context);
    }

    private static bool IsLoopbackAddress(IPAddress? address)
    {
        if (address is null)
        {
            return true;
        }

        if (IPAddress.IsLoopback(address))
        {
            return true;
        }

        if (address.IsIPv4MappedToIPv6)
        {
            return IPAddress.IsLoopback(address.MapToIPv4());
        }

        return false;
    }

    private static async Task ReturnUnauthorizedAsync(HttpContext context, string detail)
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        context.Response.ContentType = "application/json; charset=utf-8";
        await context.Response.WriteAsJsonAsync(new { detail });
    }
}
