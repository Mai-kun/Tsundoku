using System.Diagnostics;
using System.Net;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;

namespace MediaTracker.Server.Features.Settings.ProxySettings;

public sealed record TestProxyCommand(
    string? ProxyUrl,
    string? Username,
    string? Password,
    bool UseStoredPassword);

/// <summary>Тот же контракт, что и у проверки источника: статус + latency.</summary>
public sealed record ProxyTestResult(bool Success, int LatencyMs, string Message);

public interface ITestProxyHandler
{
    Task<Result<ProxyTestResult>> HandleAsync(TestProxyCommand command, CancellationToken ct);
}

/// <summary>
/// Лёгкий тестовый запрос через заданный адрес прокси: проверяет и схему (http/https/socks5),
/// и авторизацию, и достижимость цели, возвращает latency. Кандидат берётся из формы
/// (можно проверить до сохранения); пустой пароль с флагом UseStoredPassword — берётся
/// расшифрованный сохранённый. Лёгкая цель — trace-эндпоинт Cloudflare: крошечный ответ,
/// отвечает 200 почти из любой сети и не требует ключей.
/// </summary>
public sealed class TestProxyHandler(
    AppDbContext db,
    IEncryptionService encryption) : ITestProxyHandler
{
    public const string ProbeUrl = "https://www.cloudflare.com/cdn-cgi/trace";

    public async Task<Result<ProxyTestResult>> HandleAsync(TestProxyCommand command, CancellationToken ct)
    {
        var password = command.UseStoredPassword
            ? DecryptStoredPassword(ct)
            : (string.IsNullOrEmpty(command.Password) ? null : command.Password);

        var (snapshot, error) = ProxySettingsSnapshot.Build(
            enabled: true, command.ProxyUrl, command.Username, password, []);
        if (error is not null || snapshot.ProxyUri is null)
        {
            return Result<ProxyTestResult>.Failure(
                Error.Validation(error ?? "Proxy URL is required."));
        }

        try
        {
            using var handler = new SocketsHttpHandler
            {
                UseProxy = true,
                Proxy = snapshot.BuildWebProxy(),
                ConnectTimeout = TimeSpan.FromSeconds(8),
            };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(12) };

            var sw = Stopwatch.StartNew();
            using var response = await client.GetAsync(ProbeUrl, HttpCompletionOption.ResponseHeadersRead, ct);
            sw.Stop();

            // Любой ответ HTTP (даже 4xx) доказывает, что туннель через прокси работает:
            // ошибка соединения/авторизации на прокси дала бы исключение, а не статус.
            return Result<ProxyTestResult>.Success(new ProxyTestResult(
                true,
                (int)sw.ElapsedMilliseconds,
                $"OK (HTTP {(int)response.StatusCode})"));
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException)
        {
            var reason = ex.Message;
            if (ex.InnerException is not null)
            {
                reason = $"{reason} ({ex.InnerException.Message})";
            }

            return Result<ProxyTestResult>.Success(new ProxyTestResult(false, 0, reason));
        }
    }

    private string? DecryptStoredPassword(CancellationToken ct)
    {
        var blob = ProxySettingsStorage.Read(db, ct);
        return string.IsNullOrWhiteSpace(blob.PasswordEncrypted)
            ? null
            : encryption.Decrypt(blob.PasswordEncrypted);
    }
}
