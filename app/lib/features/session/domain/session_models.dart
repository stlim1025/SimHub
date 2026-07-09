/// 체크인 세션(04 §3.4~3.6). 랩-사용자 귀속의 단위(D-2).
class DriveSession {
  const DriveSession({
    required this.sessionId,
    required this.rigCode,
    required this.status,
    required this.startedAt,
  });

  final String sessionId;
  final String rigCode;
  final String status;
  final DateTime startedAt;

  factory DriveSession.fromJson(Map<String, dynamic> json) => DriveSession(
        sessionId: json['sessionId'] as String,
        rigCode: json['rigCode'] as String,
        status: json['status'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
      );
}
