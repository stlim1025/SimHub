namespace SimCenter.Application.Common;

/// <summary>
/// 외부 입력 문자열을 enum 이름으로만 해석한다(대소문자 무시). <c>Enum.TryParse</c>와 달리
/// 숫자 문자열("1")·쉼표 목록·공백이 낀 값은 이름이 아니므로 거부한다.
/// 엄격한 검증(모르는 값 → 400)은 이 메서드를, 느슨한 해석(모르는 값 → 0번)은 <see cref="LenientEnum"/>을 쓴다.
/// </summary>
public static class EnumNames
{
    public static bool TryParse<TEnum>(string? value, out TEnum result) where TEnum : struct, Enum
    {
        if (!string.IsNullOrEmpty(value))
        {
            foreach (var name in Enum.GetNames<TEnum>())
            {
                if (string.Equals(name, value, StringComparison.OrdinalIgnoreCase))
                {
                    result = Enum.Parse<TEnum>(name);
                    return true;
                }
            }
        }

        result = default;
        return false;
    }
}
