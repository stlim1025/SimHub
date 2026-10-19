import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/util/lap_time.dart';
import '../../../core/widgets/app_notice.dart';
import '../../lap_detail/domain/lap_detail_display.dart';
import '../../laps/domain/lap_models.dart';

/// 새 랩 알림이 떠 있는 시간(D-50). 동작 버튼이 있어도 저절로 사라진다.
const Duration kNewLapSnackBarDuration = Duration(seconds: 6);

const String _viewLabel = '보기';
const String _validMark = '✓';
const String _invalidMark = '✕';

/// 알림 문구: "새 랩 1:38.448 · Jeddah ✓"(무효 랩은 ✕, docs/15 §9).
String newLapMessage(Lap lap) =>
    '새 랩 ${formatLapTime(lap.lapTimeMs)} · ${lap.trackName} ${lap.isValid ? _validMark : _invalidMark}';

/// 오른쪽 위에 새 랩 알림을 띄운다(D-50, 웹 알림 방식). [보기]를 누르면 그 랩 상세로 가고, 화면을 저절로 넘기지는 않는다.
/// 앞선 알림이 떠 있으면 바로 바꾼다(여러 랩이 쌓여 줄 서지 않게).
void showNewLapSnackBar(BuildContext context, Lap lap) {
  final router = GoRouter.of(context);
  AppToaster.of(context).show(
    newLapMessage(lap),
    key: ValueKey('new-lap-${lap.lapId}'),
    tone: lap.isValid ? NoticeTone.success : NoticeTone.info,
    duration: kNewLapSnackBarDuration,
    actionLabel: _viewLabel,
    onAction: () => router.go(lapDetailLocation(lap.lapId)),
  );
}
