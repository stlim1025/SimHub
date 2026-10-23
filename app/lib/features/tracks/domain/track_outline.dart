import 'dart:ui';

/// 서킷 윤곽 하나(달리지 않은 트랙의 트랙 그림). 점은 0~1로 정규화했고 긴 변이 1이다(북쪽이 위).
/// 출처: bacinger/f1-circuits GeoJSON(MIT) — `assets/track_outlines/`.
class TrackOutline {
  const TrackOutline({required this.width, required this.height, required this.points});

  /// 정규화 폭·높이(긴 쪽이 1). 그릴 때 가로세로 비율로 쓴다.
  final double width;
  final double height;
  final List<Offset> points;
}

/// asset JSON(`{"tracks": {"이름": {"w", "h", "points": [[x, y], …]}}}`) → 트랙 이름별 윤곽. 형식이 틀린 항목은 건너뛴다.
Map<String, TrackOutline> parseTrackOutlines(Map<String, dynamic> json) {
  final tracks = json['tracks'];
  if (tracks is! Map<String, dynamic>) {
    return const {};
  }
  final result = <String, TrackOutline>{};
  for (final MapEntry(:key, :value) in tracks.entries) {
    if (value is! Map<String, dynamic>) {
      continue;
    }
    final w = value['w'];
    final h = value['h'];
    final rawPoints = value['points'];
    if (w is! num || h is! num || rawPoints is! List) {
      continue;
    }
    final points = [
      for (final p in rawPoints)
        if (p is List && p.length == 2 && p[0] is num && p[1] is num) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    if (points.length > 1) {
      result[key] = TrackOutline(width: w.toDouble(), height: h.toDouble(), points: points);
    }
  }
  return result;
}
