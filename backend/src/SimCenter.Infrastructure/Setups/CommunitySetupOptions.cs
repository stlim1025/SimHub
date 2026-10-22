using SimCenter.Domain.Constants;

namespace SimCenter.Infrastructure.Setups;

/// <summary>
/// 커뮤니티 셋업 갱신 설정(appsettings "CommunitySetups" 섹션). 기본은 꺼짐 — 운영(appsettings.Production.json)에서만 켠다.
/// 출처(F1Laps) 공개 페이지만 읽고(robots.txt 허용 경로), 요청마다 <see cref="RequestDelay"/>만큼 쉰다.
/// </summary>
public sealed class CommunitySetupOptions
{
    public const string SectionName = "CommunitySetups";

    /// <summary>요청 User-Agent(우리를 밝힌다).</summary>
    public const string UserAgent = "SimHub/1.0 (personal stats app)";

    /// <summary>주기 갱신을 돌릴지.</summary>
    public bool Enabled { get; set; }

    /// <summary>갱신 주기.</summary>
    public TimeSpan Interval { get; set; } = TimeSpan.FromHours(24);

    /// <summary>요청 사이 간격(출처 부하 제한). 테스트는 0.</summary>
    public TimeSpan RequestDelay { get; set; } = TimeSpan.FromSeconds(2);

    /// <summary>트랙·조건마다 저장할 상위 셋업 수.</summary>
    public int TopCount { get; set; } = 10;

    /// <summary>갱신할 게임 코드(배열이라 설정 값이 기본값을 대체한다).</summary>
    public string[] Games { get; set; } = [GameCodes.F1_25, GameCodes.F1_26];

    /// <summary>호스트 시작 후 첫 갱신까지 기다리는 시간(시작 직후 부하 회피).</summary>
    public TimeSpan StartupDelay { get; set; } = TimeSpan.FromMinutes(1);

    /// <summary>요청 하나의 제한 시간.</summary>
    public TimeSpan RequestTimeout { get; set; } = TimeSpan.FromSeconds(30);

    /// <summary>출처 주소(끝에 <c>/</c>).</summary>
    public string BaseUrl { get; set; } = "https://www.f1laps.com/";
}
