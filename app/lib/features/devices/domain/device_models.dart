/// 내 계정에 연결된 Agent PC 한 대(`GET /me/agent-devices`, docs/11 §8).
/// [lastSeenAt]은 서버가 이 장치에서 마지막으로 데이터를 받은 시각이며, 아직 한 번도 없으면 null.
class AgentDevice {
  const AgentDevice({
    required this.deviceId,
    required this.name,
    required this.lastSeenAt,
    required this.createdAt,
  });

  final String deviceId;
  final String name;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  factory AgentDevice.fromJson(Map<String, dynamic> json) {
    final lastSeen = json['lastSeenAt'] as String?;
    return AgentDevice(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String,
      lastSeenAt: lastSeen == null ? null : DateTime.parse(lastSeen),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// 1회용 연결 코드(`POST /me/agent-pairing-codes`). 만료 시각 이후에는 쓸 수 없다.
/// 코드 값은 민감 정보라 로그에 남기지 않는다.
class PairingCode {
  const PairingCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;

  factory PairingCode.fromJson(Map<String, dynamic> json) => PairingCode(
        code: json['code'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}
