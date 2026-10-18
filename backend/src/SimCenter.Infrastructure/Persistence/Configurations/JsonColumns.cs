namespace SimCenter.Infrastructure.Persistence.Configurations;

/// <summary>JSON 원문을 담는 열의 PostgreSQL 형식(D-49). 문자열 속성을 jsonb로 매핑한다 — DB가 저장 시 JSON 문법을 한 번 더 확인한다.</summary>
internal static class JsonColumns
{
    public const string Jsonb = "jsonb";
}
