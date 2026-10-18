using SimCenter.Domain.Common;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 앱 사용자(회원). 앱에서 직접 self-signup 한다(D-11). 랩 귀속의 주체.
/// 프로필 설정(공개 여부·프로필 사진·게임 환경·타임존·테마)도 함께 가진다(14, D-39).
/// </summary>
public class User : BaseEntity
{
    /// <summary>로그인 식별자. Unique.</summary>
    public required string Email { get; set; }

    /// <summary>비밀번호 해시(BCrypt). 평문은 저장하지 않는다.</summary>
    public required string PasswordHash { get; set; }

    /// <summary>랭킹 공개명(1~50자).</summary>
    public required string DisplayName { get; set; }

    /// <summary>랭킹에 내 표시 이름을 보일지. false면 랭킹 항목이 "익명 드라이버"로 보인다(D-39).</summary>
    public bool ShowOnLeaderboard { get; set; } = UserProfileDefaults.ShowOnLeaderboard;

    /// <summary>프로필 사진 팀 코드(<see cref="AvatarTeamCodes"/>). null이면 이름 첫 글자를 보인다.</summary>
    public string? AvatarTeam { get; set; }

    /// <summary>주로 하는 게임 코드(<see cref="GameCodes"/>). 저장만 한다(이후 Phase).</summary>
    public string PreferredGame { get; set; } = UserProfileDefaults.PreferredGame;

    /// <summary>입력 장치. 저장만 한다(이후 Phase).</summary>
    public ControllerType Controller { get; set; } = UserProfileDefaults.Controller;

    /// <summary>플랫폼. 저장만 한다(이후 Phase).</summary>
    public ConsolePlatform Console { get; set; } = UserProfileDefaults.Console;

    /// <summary>속도·거리 단위. 저장만 한다(텔레메트리 화면에서 쓴다).</summary>
    public UnitSystem Units { get; set; } = UserProfileDefaults.Units;

    /// <summary>사용자 IANA 타임존 ID. 저장만 한다 — 랭킹 기간 경계는 서버 설정을 따른다(D-27).</summary>
    public string TimeZoneId { get; set; } = UserProfileDefaults.TimeZoneId;

    /// <summary>앱 화면 테마.</summary>
    public ThemePreference Theme { get; set; } = UserProfileDefaults.Theme;

    /// <summary>내 계정에 연결된 Agent 장치(해제된 장치는 전역 필터로 제외).</summary>
    public ICollection<AgentDevice> AgentDevices { get; set; } = new List<AgentDevice>();
}
