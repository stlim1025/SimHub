using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.AgentDevices;

/// <summary>
/// Agent 연결 유스케이스(11 §4). Domain·포트에만 의존(프레임워크 무의존) → Fake 주입 단위 테스트 가능.
/// 코드·장치 키 원문은 응답으로만 나가고 저장은 해시만 한다. 코드가 없음·만료·사용됨·무효화됨인 경우는
/// 추측 공격에 힌트를 주지 않도록 모두 같은 오류로 응답한다.
/// </summary>
public sealed class AgentPairingService : IAgentPairingService
{
    private static readonly TimeSpan CodeTtl = TimeSpan.FromMinutes(10);

    private const int MaxCodeGenerationAttempts = 3;
    private const int DeviceNameMaxLength = 50;
    private const string DefaultDeviceName = "Windows PC";
    private const string InvalidCodeMessage = "유효하지 않거나 만료된 코드입니다.";

    private readonly IAgentPairingCodeRepository _codes;
    private readonly IAgentDeviceRepository _devices;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ITransactionRunner _transactions;
    private readonly IApiKeyHasher _hasher;
    private readonly IRandomSource _random;
    private readonly IIdGenerator _idGenerator;
    private readonly IClock _clock;

    public AgentPairingService(
        IAgentPairingCodeRepository codes,
        IAgentDeviceRepository devices,
        IUnitOfWork unitOfWork,
        ITransactionRunner transactions,
        IApiKeyHasher hasher,
        IRandomSource random,
        IIdGenerator idGenerator,
        IClock clock)
    {
        _codes = codes;
        _devices = devices;
        _unitOfWork = unitOfWork;
        _transactions = transactions;
        _hasher = hasher;
        _random = random;
        _idGenerator = idGenerator;
        _clock = clock;
    }

    public async Task<PairingCodeResponse> IssueCodeAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        var now = _clock.UtcNow;

        var (code, codeHash) = await CreateUniqueCodeAsync(cancellationToken);

        // 이전 미사용 코드 무효화와 신규 저장은 한 번의 SaveChanges(=한 트랜잭션)로 커밋한다.
        var previousCodes = await _codes.GetUnconsumedByUserAsync(userId, cancellationToken);
        foreach (var previous in previousCodes)
        {
            previous.IsDeleted = true;
            previous.UpdatedAt = now;
        }

        var expiresAt = now.Add(CodeTtl);
        await _codes.AddAsync(
            new AgentPairingCode
            {
                Id = _idGenerator.NewId(),
                UserId = userId,
                CodeHash = codeHash,
                ExpiresAt = expiresAt,
                CreatedAt = now,
            },
            cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        return new PairingCodeResponse(PairingCodeFormat.Display(code), expiresAt);
    }

    /// <summary>
    /// 해시가 기존 코드(soft delete 포함)와 겹치지 않는 코드를 만든다. 고유 인덱스 충돌을 피하려고
    /// 겹치면 다시 만들고, <see cref="MaxCodeGenerationAttempts"/>회 안에 못 찾으면 예외(→ 500).
    /// </summary>
    private async Task<(string Code, string CodeHash)> CreateUniqueCodeAsync(CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < MaxCodeGenerationAttempts; attempt++)
        {
            var code = PairingCodeFormat.Create(_random);
            var codeHash = _hasher.Hash(code);

            if (!await _codes.ExistsByHashAsync(codeHash, cancellationToken))
            {
                return (code, codeHash);
            }
        }

        throw new InvalidOperationException(
            $"연결 코드를 {MaxCodeGenerationAttempts}회 시도했지만 고유한 값을 만들지 못했습니다.");
    }

    public async Task<PairResponse> PairAsync(PairRequest request, CancellationToken cancellationToken = default)
    {
        var deviceName = NormalizeDeviceName(request.DeviceName);

        var code = PairingCodeFormat.Normalize(request.Code);
        if (code.Length != PairingCodeFormat.Length)
        {
            throw InvalidCode();
        }

        var codeHash = _hasher.Hash(code);

        // 코드 소비와 장치 생성은 한 트랜잭션: 장치 저장이 실패하면 소비도 되돌려 코드를 다시 쓸 수 있다.
        return await _transactions.RunAsync(
            async token =>
            {
                var now = _clock.UtcNow;

                var pairingCode = await _codes.GetRedeemableByHashAsync(codeHash, now, token)
                    ?? throw InvalidCode();

                // 조건부 UPDATE로 원자적으로 소비 — 동시에 같은 코드로 연결해도 하나만 성공한다.
                if (!await _codes.TryConsumeAsync(pairingCode.Id, now, token))
                {
                    throw InvalidCode();
                }

                var deviceKey = DeviceKeyFormat.Create(_random);
                var device = new AgentDevice
                {
                    Id = _idGenerator.NewId(),
                    UserId = pairingCode.UserId,
                    Name = deviceName,
                    ApiKeyHash = _hasher.Hash(deviceKey),
                    CreatedAt = now,
                };

                await _devices.AddAsync(device, token);
                await _unitOfWork.SaveChangesAsync(token);

                return new PairResponse(device.Id, deviceKey);
            },
            cancellationToken);
    }

    private static string NormalizeDeviceName(string? deviceName)
    {
        var name = (deviceName ?? string.Empty).Trim();
        if (name.Length == 0)
        {
            return DefaultDeviceName;
        }

        if (name.Length > DeviceNameMaxLength)
        {
            throw new ValidationException("deviceName", $"장치 이름은 {DeviceNameMaxLength}자 이하여야 합니다.");
        }

        return name;
    }

    private static ValidationException InvalidCode() => new("code", InvalidCodeMessage);
}
