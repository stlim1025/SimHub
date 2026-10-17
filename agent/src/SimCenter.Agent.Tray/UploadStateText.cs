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

    /// <summary>이 PC에 유효하게 연결돼 있다고 볼 수 있는 상태인가(Unauthorized는 키는 있으나 거부된 상태라 포함).</summary>
    public static bool IsLinked(UploadState state) =>
        state is UploadState.Connecting or UploadState.Connected or UploadState.Unauthorized;
}
