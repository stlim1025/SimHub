namespace SimCenter.Infrastructure.Identity;

/// <summary>
/// JWT 설정(appsettings "Jwt" 섹션). 서명 키는 코드에 두지 않고 설정/User-Secrets로 주입한다(헌장 Security).
/// </summary>
public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    public string Issuer { get; set; } = string.Empty;
    public string Audience { get; set; } = string.Empty;
    public string Key { get; set; } = string.Empty;
    public int ExpiryMinutes { get; set; } = 120;
}
