using SimCenter.Agent.Infrastructure.Upload;

namespace SimCenter.Agent.Tray;

/// <summary>업로드 상태 → "계정 연결" 영역 표시 문자열(한국어). 화면과 분리된 순수 매핑(docs/11 §6.3).</summary>
internal static class UploadStateText
{
    public static string Describe(UploadState state, string deviceName) => state switch
    {
        UploadState.Connecting or UploadState.Connected => $"연결됨 · {deviceName}",
        UploadState.Unauthorized => "다시 연결 필요",
        UploadState.Disabled => "업로드 꺼짐(ServerBaseUrl 비어 있음)",
        _ => "미연결", // Unpaired
    };

    /// <summary>
    /// 올리지 못한 기록 안내(docs/13 §3.5). 미뤄 둔 항목은 자동으로 다시 보내고, dead-letter 항목은 보관만 한다. 둘 다 0건이면 null(숨김).
    /// </summary>
    public static string? DescribeIssues(int deferredCount, int deadLetterCount)
    {
        var lines = new List<string>();
        if (deferredCount > 0)
        {
            lines.Add($"서버가 처리하지 못한 기록 {deferredCount}건 — 자동으로 다시 보냅니다");
        }

        if (deadLetterCount > 0)
        {
            lines.Add($"읽을 수 없어 따로 보관한 기록 {deadLetterCount}건 — 로그를 확인하세요");
        }

        return lines.Count == 0 ? null : string.Join(Environment.NewLine, lines);
    }

    /// <summary>이 PC에 유효하게 연결돼 있다고 볼 수 있는 상태인가(Unauthorized는 키는 있으나 거부된 상태라 포함).</summary>
    public static bool IsLinked(UploadState state) =>
        state is UploadState.Connecting or UploadState.Connected or UploadState.Unauthorized;
}
