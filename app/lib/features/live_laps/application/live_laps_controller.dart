import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/ranking_hub_client.dart';
import '../../auth/application/auth_controller.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../devices/application/devices_providers.dart';
import '../../lap_detail/application/lap_detail_providers.dart';
import '../../laps/application/fresh_laps.dart';
import '../../laps/application/laps_providers.dart';
import '../../laps/domain/lap_models.dart';

/// 허브 연결에 실패했거나 자동 재접속도 끊겼을 때 다시 연결하기까지 기다리는 시간(D-50).
const Duration kLiveLapsRetryDelay = Duration(seconds: 15);

/// 실시간으로 받은 새 랩 한 건(D-50, docs/15 §9). 같은 랩이 다시 와도 새 알림이 되도록 순번을 둔다.
@immutable
class LiveLapEvent {
  const LiveLapEvent({required this.lap, required this.sequence});

  final Lap lap;

  /// 이 리스너가 받은 순서(1부터).
  final int sequence;
}

/// 내 새 랩 리스너(D-50, docs/15 §9). 로그인 상태에서 셸이 듣는 동안 RankingHub의 `LapRecorded`를 받는다
/// (랭킹 화면과 같은 연결을 함께 쓴다 — 허브 연결은 하나).
///
/// - 새 랩: 랩 목록 provider를 다시 불러오고, 새 랩으로 표시(강조)하고, 상태(= 마지막으로 받은 랩)를 바꾼다 → 셸이 알림을 띄운다.
/// - 재접속: 놓친 랩을 채우려 한 번 다시 불러온다(알림 없음).
/// - 연결 실패·완전히 끊김: [kLiveLapsRetryDelay] 뒤 다시 연결하고, 성공하면 다시 불러온다.
/// - 로그아웃: 사용자가 바뀌면 다시 만들어지며 이전 구독·타이머는 모두 정리된다.
class LiveLapsController extends Notifier<LiveLapEvent?> {
  int _sequence = 0;

  @override
  LiveLapEvent? build() {
    final userId = ref.watch(authControllerProvider.select((auth) => auth.valueOrNull?.userId));
    if (userId == null) {
      return null;
    }

    final hub = ref.watch(rankingHubClientProvider);
    var active = true;
    Timer? retry;

    Future<void> connect({required bool refreshOnSuccess}) async {
      try {
        await hub.connect();
        if (active && refreshOnSuccess) {
          _refreshLaps();
        }
      } catch (e) {
        debugPrint('새 랩 실시간 연결 실패(잠시 뒤 다시 시도): $e');
        if (active) {
          retry?.cancel();
          retry = Timer(kLiveLapsRetryDelay, () => unawaited(connect(refreshOnSuccess: true)));
        }
      }
    }

    final subscriptions = [
      hub.lapRecorded.listen(_onLapRecorded),
      hub.reconnected.listen((_) => _refreshLaps()),
      hub.closed.listen((_) {
        retry?.cancel();
        retry = Timer(kLiveLapsRetryDelay, () => unawaited(connect(refreshOnSuccess: true)));
      }),
    ];
    ref.onDispose(() {
      active = false;
      retry?.cancel();
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    });

    unawaited(connect(refreshOnSuccess: false));
    return null;
  }

  void _onLapRecorded(Map<String, dynamic> payload) {
    // 모양이 달라도(옛 서버) 랩이 생긴 것은 맞으므로 목록은 다시 불러온다.
    _refreshLaps();
    final lap = Lap.tryParse(payload);
    if (lap == null) {
      debugPrint('LapRecorded 페이로드를 읽지 못했어요: $payload');
      return;
    }
    ref.read(freshLapIdsProvider.notifier).mark(lap.lapId);
    _sequence++;
    state = LiveLapEvent(lap: lap, sequence: _sequence);
  }

  /// 내 랩·트랙 요약·대시보드(최근 랩·연결 상태)·최고 랩을 다시 불러온다(docs/15 §9). 보고 있지 않은 provider는 다음에 열 때 새로 읽는다.
  void _refreshLaps() {
    ref
      ..invalidate(myTracksProvider)
      ..invalidate(trackLapsProvider)
      ..invalidate(recentLapsProvider)
      ..invalidate(bestLapsProvider)
      ..invalidate(agentDevicesProvider);
  }
}

final liveLapsControllerProvider =
    NotifierProvider<LiveLapsController, LiveLapEvent?>(LiveLapsController.new);
