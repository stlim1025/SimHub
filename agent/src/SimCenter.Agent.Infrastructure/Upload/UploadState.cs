namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>업로더(<see cref="TelemetryUploadService"/>) 상태. Tray·로그가 표시용으로 읽는다(docs/11 §6.3·§6.4).</summary>
public enum UploadState
{
    /// <summary>ServerBaseUrl이 비었거나 잘못돼 업로드하지 않는다(이벤트는 Outbox에 계속 적재).</summary>
    Disabled,

    /// <summary>장치 키가 없다 — 계정 연결(pair)을 기다린다.</summary>
    Unpaired,

    /// <summary>TelemetryHub에 연결 중이거나 일시 오류로 재시도 중.</summary>
    Connecting,

    /// <summary>TelemetryHub에 연결되어 Outbox를 배수(drain)한다.</summary>
    Connected,

    /// <summary>서버가 장치 키를 거부(401)했다 — 새 키가 저장될 때까지 업로드하지 않는다("다시 연결 필요").</summary>
    Unauthorized,
}
