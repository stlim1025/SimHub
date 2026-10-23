import 'dart:ui';

/// 실측 서킷 한 곳: 닫힌 중심선(m, 약 5m 간격)과 점마다 진행 방향 기준 오른쪽·왼쪽 폭(m).
/// 출처: TUMFTM/racetrack-database(LGPL-3.0) — `assets/track_widths/`. 좌표계는 게임과 달라 쓰기 전에 주행선에 맞춰 정렬한다.
class TrackWidthProfile {
  const TrackWidthProfile({required this.center, required this.rightM, required this.leftM});

  final List<Offset> center;
  final List<double> rightM;
  final List<double> leftM;

  int get length => center.length;
}

/// 실측 데이터가 없는 트랙 가운데 기본 추정 폭(13m)과 크게 다른 곳의 직선 도로 폭(m).
/// 모나코: 공개 자료의 대략값(가장 좁은 곳 약 8m, 넓은 곳 10~11m) — 공식 수치는 아니다. 시가지라 좁게 느껴지도록 9m로 둔다
/// (차들이 넓게 달린 곳은 표본 형상이 그만큼 넓힌다).
const Map<String, double> kEstimatedTrackWidthsM = {'Monaco': 9};

/// 시가지 서킷(앱 트랙 이름): 그래블·잔디 런오프 없이 도로 바로 옆에 방호벽이 선다.
const Set<String> kStreetCircuits = {'Monaco', 'Baku (Azerbaijan)', 'Singapore', 'Jeddah', 'Las Vegas'};

/// asset JSON(`{"tracks": {"앱 트랙 이름": "데이터 이름"}, "data": {"데이터 이름": [[x, y, 오른쪽 폭, 왼쪽 폭], …]}}`)
/// → 앱 트랙 이름별 실측 서킷. 형식이 틀린 항목은 건너뛴다.
Map<String, TrackWidthProfile> parseTrackWidths(Map<String, dynamic> json) {
  final tracks = json['tracks'];
  final data = json['data'];
  if (tracks is! Map<String, dynamic> || data is! Map<String, dynamic>) {
    return const {};
  }
  final profiles = <String, TrackWidthProfile>{};
  for (final MapEntry(:key, :value) in data.entries) {
    if (value is! List) {
      continue;
    }
    final rows = [
      for (final row in value)
        if (row is List && row.length == 4 && row.every((e) => e is num)) [for (final e in row) (e as num).toDouble()],
    ];
    if (rows.length > 2) {
      profiles[key] = TrackWidthProfile(
        center: [for (final r in rows) Offset(r[0], r[1])],
        rightM: [for (final r in rows) r[2]],
        leftM: [for (final r in rows) r[3]],
      );
    }
  }
  return {
    for (final MapEntry(:key, :value) in tracks.entries)
      if (value is String && profiles[value] != null) key: profiles[value]!,
  };
}
