using System.Net;
using MediaTracker.Server.Infrastructure.Persistence;
using Serilog;

using MediaTracker.Server.Common.Json;

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
        var isTrustedNetwork = IsTrustedLocalOrLanAddress(context.Connection.RemoteIpAddress);

        // Local loopback and LAN access without explicit token headers is trusted (frictionless UI mode)
        if (isTrustedNetwork && !hasAuthHeader)
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

        var apiToken = await db.GetApiTokenByHashAsync(tokenHash, default);

        if (apiToken is null || apiToken.ExpiresAt is { } exp && exp <= DateTime.UtcNow)
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
                    await scopeDb.UpdateApiTokenLastUsedAsync(tokenId, DateTime.UtcNow);
                }
                catch (Exception ex)
                {
                    Log.Warning(ex, "Failed to update LastUsedAt for API token {TokenId}", tokenId);
                }
            });
        }

        await next(context);
    }

    private static bool IsTrustedLocalOrLanAddress(IPAddress? address)
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
            address = address.MapToIPv4();
        }

        if (address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
        {
            if (IPAddress.IsLoopback(address))
            {
                return true;
            }

            Span<byte> bytes = stackalloc byte[4];
            if (address.TryWriteBytes(bytes, out _))
            {
                // 10.0.0.0/8 (10.x.x.x)
                if (bytes[0] == 10)
                {
                    return true;
                }

                // 172.16.0.0/12 (172.16.x.x - 172.31.x.x)
                if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31)
                {
                    return true;
                }

                // 192.168.0.0/16 (192.168.x.x)
                if (bytes[0] == 192 && bytes[1] == 168)
                {
                    return true;
                }
            }

            return false;
        }

        if (address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6)
        {
            // IPv6 Link-Local (fe80::/10)
            if (address.IsIPv6LinkLocal)
            {
                return true;
            }

            Span<byte> bytes = stackalloc byte[16];
            if (address.TryWriteBytes(bytes, out _))
            {
                // IPv6 Unique Local Address fc00::/7 (fc00::/8 and fd00::/8)
                if ((bytes[0] & 0xFE) == 0xFC)
                {
                    return true;
                }
            }

            return false;
        }

        return false;
    }

    private static async Task ReturnUnauthorizedAsync(HttpContext context, string detail)
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        context.Response.ContentType = "application/json; charset=utf-8";
        await context.Response.WriteAsJsonAsync(new ApiErrorDetail(detail), AppJsonSerializerContext.Default.ApiErrorDetail);
    }
}
