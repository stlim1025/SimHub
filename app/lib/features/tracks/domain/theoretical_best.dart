import '../../lap_detail/domain/lap_corners.dart' show OfficialCorner;
import '../../sessions/domain/session_detail_models.dart';

/// 배터리 한 통(J) — 레이스 리뷰와 같은 기준으로 배터리 양을 %로 보인다.
const double _ersCapacityJ = 4000000;
const double _joulesPerKj = 1000;
const double _percent = 100;

/// 최고 랩과 이만큼(ms) 이상 다른 구간만 표에 보인다.
const int kTheoreticalGainMinMs = 10;

/// 최고 랩과 배터리 사용이 이보다(kJ, 배터리 2.5%) 적게 다르면 같게 본다.
const double _batteryEvenKj = 100;

/// 이론상 최고 랩의 구간 하나: 랩 거리 [startM, endM)을 가장 잘 달린 랩과 그 기록, 최고 랩의 같은 구간 기록.
/// 배터리(kJ)는 배터리를 따지지 않는 조건이면 null.
class TheoreticalSegment {
  const TheoreticalSegment({
    required this.index,
    required this.startM,
    required this.endM,
    required this.lapId,
    required this.lapSetAt,
    required this.timeMs,
    required this.bestLapTimeMs,
    this.deployKj,
    this.harvestKj,
    this.bestLapDeployKj,
    this.bestLapHarvestKj,
  });

  final int index;
  final int startM;
  final int endM;
  final String lapId;
  final DateTime lapSetAt;
  final int timeMs;
  final int bestLapTimeMs;
  final double? deployKj;
  final double? harvestKj;
  final double? bestLapDeployKj;
  final double? bestLapHarvestKj;

  /// 최고 랩보다 줄어드는 시간(ms, 0 이하).
  int get gainMs => timeMs - bestLapTimeMs;

  static TheoreticalSegment? fromJsonOrNull(Map<String, dynamic> json) {
    final index = jsonInt(json['index']);
    final startM = jsonInt(json['startM']);
    final endM = jsonInt(json['endM']);
    final lapId = jsonString(json['lapId']);
    final setAt = DateTime.tryParse(jsonString(json['lapSetAt']) ?? '');
    final timeMs = jsonInt(json['timeMs']);
    final bestLapTimeMs = jsonInt(json['bestLapTimeMs']);
    if (index == null || startM == null || endM == null || lapId == null || setAt == null || timeMs == null || bestLapTimeMs == null) {
      return null;
    }
    return TheoreticalSegment(
      index: index,
      startM: startM,
      endM: endM,
      lapId: lapId,
      lapSetAt: setAt,
      timeMs: timeMs,
      bestLapTimeMs: bestLapTimeMs,
      deployKj: jsonDouble(json['deployKj']),
      harvestKj: jsonDouble(json['harvestKj']),
      bestLapDeployKj: jsonDouble(json['bestLapDeployKj']),
      bestLapHarvestKj: jsonDouble(json['bestLapHarvestKj']),
    );
  }
}

/// 한 조건(세션 종류 + 컴파운드)의 이론상 최고 랩(`GET /tracks/{trackId}/theoretical-best`의 `groups[]`).
/// [theoreticalMs] = 배터리 한도를 지킨 값, [unlimitedMs] = 배터리를 무시한 구간 최고 기록의 합.
class TheoreticalBestGroup {
  const TheoreticalBestGroup({
    required this.sessionType,
    required this.lapCount,
    required this.lapLengthM,
    required this.bestLapId,
    required this.bestLapMs,
    required this.theoreticalMs,
    required this.unlimitedMs,
    required this.hasBattery,
    required this.segments,
    this.visualTyreCompound,
    this.isWet = false,
  });

  final String sessionType;
  final int? visualTyreCompound;

  /// 랩 끝 날씨가 약한 비 이상인 조건(마른 노면 랩과 따로 잇는다).
  final bool isWet;
  final int lapCount;
  final int lapLengthM;
  final String bestLapId;
  final int bestLapMs;
  final int theoreticalMs;
  final int unlimitedMs;
  final bool hasBattery;
  final List<TheoreticalSegment> segments;

  /// 최고 랩보다 줄일 수 있는 시간(ms, 0 이하).
  int get gainMs => theoreticalMs - bestLapMs;

  /// 배터리 한도 때문에 못 쓰는 시간(ms, 0 이상) — 구간 최고 기록끼리 이으면 한 랩에 쓸 수 있는 배터리를 넘는다.
  int get batteryLimitMs => theoreticalMs - unlimitedMs;

  /// 최고 랩과 [kTheoreticalGainMinMs] 이상 다른 구간, 많이 줄어드는 순(느려지는 구간은 뒤). 느려지는 구간은 다른 곳에 쓸 배터리를 아끼는 자리다.
  List<TheoreticalSegment> get changes =>
      [for (final s in segments) if (s.gainMs.abs() >= kTheoreticalGainMinMs) s]..sort((a, b) => a.gainMs.compareTo(b.gainMs));

  static TheoreticalBestGroup? fromJsonOrNull(Map<String, dynamic> json) {
    final sessionType = jsonString(json['sessionType']);
    final bestLapId = jsonString(json['bestLapId']);
    final bestLapMs = jsonInt(json['bestLapMs']);
    final theoreticalMs = jsonInt(json['theoreticalMs']);
    final segments = jsonObjects(json['segments'], TheoreticalSegment.fromJsonOrNull);
    if (sessionType == null || bestLapId == null || bestLapMs == null || theoreticalMs == null || segments.isEmpty) {
      return null;
    }
    return TheoreticalBestGroup(
      sessionType: sessionType,
      visualTyreCompound: jsonInt(json['visualTyreCompound']),
      isWet: jsonBool(json['isWet']),
      lapCount: jsonInt(json['lapCount']) ?? 0,
      lapLengthM: jsonInt(json['lapLengthM']) ?? 0,
      bestLapId: bestLapId,
      bestLapMs: bestLapMs,
      theoreticalMs: theoreticalMs,
      unlimitedMs: jsonInt(json['unlimitedMs']) ?? theoreticalMs,
      hasBattery: jsonBool(json['hasBattery']),
      segments: segments,
    );
  }
}

/// 응답의 조건 목록(형식이 틀린 조건은 버린다).
List<TheoreticalBestGroup> parseTheoreticalBest(Map<String, dynamic> json) =>
    jsonObjects(json['groups'], TheoreticalBestGroup.fromJsonOrNull);

/// 구간 이름(구간 순서): 그 안의 공식 코너(`T1`·`T4~T5`). 공식 코너를 모르거나 구간에 없으면 `구간 3`.
/// 구간이 랩을 빈틈없이 덮으므로 공식 코너는 한 구간에만 든다.
List<String> theoreticalSegmentLabels(TheoreticalBestGroup group, List<OfficialCorner>? corners) {
  final length = group.lapLengthM;
  String labelOf(TheoreticalSegment s) {
    final inside = [
      if (corners != null && length > 0)
        for (final c in corners)
          if (c.fraction * length >= s.startM && c.fraction * length < s.endM) 'T${c.number}${c.letter}',
    ];
    return switch (inside) {
      [] => '구간 ${s.index + 1}',
      [final only] => only,
      [final first, ..., final last] => '$first~$last',
    };
  }

  return [for (final s in group.segments) labelOf(s)];
}

/// 최고 랩 대비 배터리 차이(`씀 +26% · 채움 +23%`). 둘 다 [_batteryEvenKj]보다 작게 다르면 `같음`, 배터리를 모르면 null.
String? theoreticalBatteryDelta(TheoreticalSegment s) {
  final deploy = s.deployKj;
  final harvest = s.harvestKj;
  final bestDeploy = s.bestLapDeployKj;
  final bestHarvest = s.bestLapHarvestKj;
  if (deploy == null || harvest == null || bestDeploy == null || bestHarvest == null) {
    return null;
  }
  final parts = [
    if ((deploy - bestDeploy).abs() >= _batteryEvenKj) '씀 ${_signedShare(deploy - bestDeploy)}',
    if ((harvest - bestHarvest).abs() >= _batteryEvenKj) '채움 ${_signedShare(harvest - bestHarvest)}',
  ];
  return parts.isEmpty ? '같음' : parts.join(' · ');
}

/// 배터리 양(kJ)을 배터리 한 통 대비 부호 있는 %로(`+26%`·`-9%`).
String _signedShare(double kj) {
  final percent = (kj * _joulesPerKj / _ersCapacityJ * _percent).round();
  return percent > 0 ? '+$percent%' : '$percent%';
}
