import 'lap_detail_models.dart';

/// 공유 링크로 보는 랩(`GET /public/laps/{lapId}`, 로그인 없음). 상세는 [LapDetail]과 같은 모양의 부분집합 —
/// 세션 연결·비교 대상은 없다(늘 null). [displayName] = 랩 주인 이름(이름 비공개면 서버가 `익명 드라이버`로 보낸다).
class SharedLap {
  const SharedLap({required this.detail, required this.displayName});

  final LapDetail detail;
  final String displayName;

  factory SharedLap.fromJson(Map<String, dynamic> json) => SharedLap(
        detail: LapDetail.fromJson(json),
        displayName: json['displayName'] as String? ?? '',
      );
}
