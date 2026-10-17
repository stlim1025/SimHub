using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Credentials;

namespace SimCenter.Agent.Infrastructure.Pairing;

/// <summary>
/// <c>POST {ServerBaseUrl}/api/v1/agent/pair</c>로 연결 코드를 장치 키로 바꾸고 <see cref="IDeviceCredentialStore"/>에 저장한다.
/// 데스크톱 단일 프로세스 에이전트라 <see cref="HttpClient"/> 하나를 프로세스 수명 동안 재사용한다(소유·해제는 만든 쪽이 한다).
/// 연결 코드와 장치 키 원문은 로그·결과 메시지에 남기지 않는다(docs/11 §9).
/// </summary>
public sealed class AgentPairingClient : IAgentPairingClient
{
    /// <summary>연결 요청 한 번의 제한 시간. 사람이 기다리는 대화형 작업이라 짧게 둔다.</summary>
    public static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(15);

    private const string InvalidCodeMessage = "유효하지 않거나 만료된 코드입니다.";
    private const string TooManyRequestsMessage = "요청이 너무 많습니다. 잠시 후 다시 시도하세요.";
    private const string CodeRequiredMessage = "연결 코드를 입력하세요.";
    private const string InvalidServerUrlMessage =
        "서버 주소(Agent:ServerBaseUrl)가 설정되지 않았거나 올바르지 않습니다. appsettings.json을 확인하세요.";
    private const string UnreadableResponseMessage = "서버 응답을 해석할 수 없습니다. 잠시 후 다시 시도하세요.";
    private const string SaveFailedMessage =
        "연결은 승인되었지만 장치 키를 이 PC에 저장하지 못했습니다. 웹에서 새 연결 코드를 발급해 다시 시도하세요.";
    private const string SucceededMessage = "연결되었습니다. 이제 Agent를 실행하면 기록이 이 계정에 업로드됩니다.";

    private readonly HttpClient _http;
    private readonly IDeviceCredentialStore _credentials;
    private readonly IOptions<AgentOptions> _options;
    private readonly ILogger<AgentPairingClient> _logger;

    public AgentPairingClient(
        HttpClient http,
        IDeviceCredentialStore credentials,
        IOptions<AgentOptions> options,
        ILogger<AgentPairingClient> logger)
    {
        ArgumentNullException.ThrowIfNull(http);
        ArgumentNullException.ThrowIfNull(credentials);
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(logger);
        _http = http;
        _credentials = credentials;
        _options = options;
        _logger = logger;
    }

    public async Task<PairOutcome> PairAsync(string code, string deviceName, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(deviceName);

        if (string.IsNullOrWhiteSpace(code))
        {
            return Fail(CodeRequiredMessage);
        }

        var pairUri = ResolvePairUri();
        if (pairUri is null)
        {
            return Fail(InvalidServerUrlMessage);
        }

        HttpResponseMessage response;
        try
        {
            response = await _http.PostAsJsonAsync(pairUri, new PairRequest(code, deviceName), ct);
        }
        catch (Exception ex) when (ex is HttpRequestException || (ex is OperationCanceledException && !ct.IsCancellationRequested))
        {
            // 호출자 취소가 아닌 취소는 HttpClient.Timeout 만료다. 요청 본문(코드)은 예외 메시지에 실리지 않는다.
            // 대화형 CLI 콘솔에 스택 트레이스가 쏟아지지 않도록 예외 객체 대신 종류·메시지만 남긴다.
            _logger.LogWarning(
                "연결 서버에 닿지 못했습니다 server={Server} error={ErrorType}: {ErrorMessage}",
                pairUri.Authority,
                ex.GetType().Name,
                ex.Message);
            return Fail($"서버에 연결할 수 없습니다 ({pairUri.Authority}). 서버 주소와 실행 여부를 확인하세요.");
        }

        using (response)
        {
            return await HandleResponseAsync(response, ct);
        }
    }

    private Uri? ResolvePairUri()
    {
        try
        {
            return AgentEndpoints.PairUri(_options.Value.ServerBaseUrl);
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    private async Task<PairOutcome> HandleResponseAsync(HttpResponseMessage response, CancellationToken ct)
    {
        switch (response.StatusCode)
        {
            case HttpStatusCode.OK:
                return await SaveIssuedKeyAsync(response, ct);
            case HttpStatusCode.BadRequest:
                // 코드 없음·만료·사용됨·무효화됨은 서버가 같은 400으로 응답한다(추측 공격 방지, docs/11 §4.3).
                return Fail(InvalidCodeMessage);
            case HttpStatusCode.TooManyRequests:
                return Fail(TooManyRequestsMessage);
            default:
                _logger.LogWarning("연결 요청이 예상 밖 상태로 거절되었습니다 status={Status}", (int)response.StatusCode);
                return Fail($"서버가 연결 요청을 처리하지 못했습니다 (HTTP {(int)response.StatusCode}). 잠시 후 다시 시도하세요.");
        }
    }

    private async Task<PairOutcome> SaveIssuedKeyAsync(HttpResponseMessage response, CancellationToken ct)
    {
        PairResponse? body;
        try
        {
            body = await response.Content.ReadFromJsonAsync<PairResponse>(ct);
        }
        catch (Exception ex) when (ex is JsonException or NotSupportedException or HttpRequestException)
        {
            _logger.LogWarning(ex, "연결 응답을 읽지 못했습니다");
            return Fail(UnreadableResponseMessage);
        }

        if (string.IsNullOrWhiteSpace(body?.DeviceKey))
        {
            _logger.LogWarning("연결 응답에 장치 키가 없습니다");
            return Fail(UnreadableResponseMessage);
        }

        try
        {
            _credentials.Save(body.DeviceKey);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or CryptographicException)
        {
            // 예외 메시지에는 키 내용이 없다. 코드는 이미 소비됐으므로 새 코드가 필요하다.
            _logger.LogError(ex, "장치 키 저장에 실패했습니다");
            return Fail(SaveFailedMessage);
        }

        _logger.LogInformation("계정에 연결되었습니다");
        return new PairOutcome(true, SucceededMessage);
    }

    private static PairOutcome Fail(string message) => new(false, message);

    private sealed record PairRequest(string Code, string DeviceName);

    private sealed record PairResponse(string? DeviceKey);
}
