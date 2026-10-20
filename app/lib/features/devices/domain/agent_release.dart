/// 서버가 내려주는 Agent 설치 묶음의 빌드 정보(`GET /downloads/SimHubAgent.json`).
/// `agent/publish-agent.ps1`이 zip과 함께 만든다. 다운로드 카드에 버전·빌드 날짜·크기를 보여줄 때만 쓴다.
class AgentRelease {
  const AgentRelease({required this.version, required this.builtAt, required this.sizeBytes});

  /// 빌드 식별자(예: `e50ef1d-20261020`).
  final String version;

  /// 빌드 시각(UTC).
  final DateTime builtAt;

  /// zip 크기(바이트).
  final int sizeBytes;

  /// 필드가 빠졌거나 형식이 틀리면 null(카드는 빌드 정보 없이 버튼만 보인다).
  static AgentRelease? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final version = json['version'];
    final builtAt = json['builtAt'];
    final sizeBytes = json['sizeBytes'];
    if (version is! String || builtAt is! String || sizeBytes is! num) {
      return null;
    }
    final parsedAt = DateTime.tryParse(builtAt);
    if (version.isEmpty || parsedAt == null) {
      return null;
    }
    return AgentRelease(version: version, builtAt: parsedAt, sizeBytes: sizeBytes.toInt());
  }
}
