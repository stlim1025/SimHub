namespace SimCenter.Application.Common;

/// <summary>
/// 외부 입력 문자열을 enum으로 느슨하게 해석한다(스펙 §6.2-1). 게임 업데이트로 새 값이 생겨도
/// 세션당 한 번뿐인 이벤트를 거부하지 않도록, 모르는 값은 0번 대체값(<c>default</c>)으로 받아들인다.
/// </summary>
public static class LenientEnum
{
    /// <summary>
    /// 이름이 대소문자 무시로 일치하면 그 값, 아니면 <c>default(TEnum)</c>.
    /// 숫자 문자열("15")·쉼표 목록·공백이 낀 값은 이름이 아니므로 거부한다(<c>Enum.TryParse</c>와 다름).
    /// </summary>
    public static TEnum Parse<TEnum>(string? value) where TEnum : struct, Enum
    {
        if (string.IsNullOrEmpty(value))
        {
            return default;
        }

        foreach (var name in Enum.GetNames<TEnum>())
        {
            if (string.Equals(name, value, StringComparison.OrdinalIgnoreCase))
            {
                return Enum.Parse<TEnum>(name);
            }
        }

        return default;
    }
}
