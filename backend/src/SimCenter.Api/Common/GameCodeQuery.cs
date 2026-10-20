using SimCenter.Application.Common.Exceptions;
using SimCenter.Domain.Constants;

namespace SimCenter.Api.Common;

/// <summary>조회 엔드포인트의 선택 쿼리 <c>gameCode</c> 해석. 생략·공백이면 null(필터 없음), 지원하지 않는 코드면 400.</summary>
public static class GameCodeQuery
{
    public const string Field = "gameCode";

    /// <summary>선택 <c>gameCode</c>를 검증해 돌려준다(앞뒤 공백 제거, 대소문자 구분).</summary>
    /// <exception cref="ValidationException">지원하지 않는 게임 코드.</exception>
    public static string? ParseOptional(string? gameCode)
    {
        if (string.IsNullOrWhiteSpace(gameCode))
        {
            return null;
        }

        var code = gameCode.Trim();
        if (!GameCodes.IsSupported(code))
        {
            throw new ValidationException(Field, $"gameCode는 {string.Join('/', GameCodes.Supported)} 중 하나여야 합니다.");
        }

        return code;
    }
}
