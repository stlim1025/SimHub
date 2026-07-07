using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 앱 사용자(회원). 앱에서 직접 self-signup 한다(D-11). 랩 귀속의 주체.
/// </summary>
public class User : BaseEntity
{
    /// <summary>로그인 식별자. Unique.</summary>
    public required string Email { get; set; }

    /// <summary>비밀번호 해시(BCrypt). 평문은 저장하지 않는다.</summary>
    public required string PasswordHash { get; set; }

    /// <summary>랭킹 공개명(1~50자).</summary>
    public required string DisplayName { get; set; }

    public ICollection<DrivingSession> Sessions { get; set; } = new List<DrivingSession>();
}
