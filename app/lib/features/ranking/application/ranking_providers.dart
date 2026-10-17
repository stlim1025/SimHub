import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/ranking_hub_client.dart';
import '../data/ranking_repository.dart';
import '../domain/ranking_models.dart';

/// 랭킹 기간(서버 `period` 값). 기본 기준은 월별(D-8a).
const String kRankingPeriodDaily = 'daily';
const String kRankingPeriodMonthly = 'monthly';
const String kRankingPeriodYearly = 'yearly';

/// RankingHub가 브로드캐스트하는 스냅샷의 기간. 허브는 월별 랭킹만 보낸다(05 §3).
const String kHubSnapshotPeriod = kRankingPeriodMonthly;

/// 트랙 마스터 목록.
final tracksProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(rankingRepositoryProvider).getTracks(),
);

/// 랭킹 조회 조건(트랙 + 기간). 값 동등성으로 provider family 키가 된다.
@immutable
class RankingQuery {
  const RankingQuery({required this.trackId, this.period = kRankingPeriodMonthly});

  final String trackId;
  final String period;

  @override
  bool operator ==(Object other) =>
      other is RankingQuery && other.trackId == trackId && other.period == period;

  @override
  int get hashCode => Object.hash(trackId, period);

  @override
  String toString() => 'RankingQuery($trackId, $period)';
}

/// 허브 스냅샷을 그대로 화면에 반영해도 되는지. 같은 트랙의 월별 조회일 때만 참이다.
bool shouldApplyHubSnapshot(RankingQuery query, Map<String, dynamic> payload) =>
    query.period == kHubSnapshotPeriod && payload['trackId'] == query.trackId;

/// 트랙 허브 구독. 같은 트랙을 보는 컨트롤러(기간만 다른 경우 등)가 모두 사라지면 구독을 해제한다.
/// 컨트롤러가 이 provider를 watch하므로, 기간만 바꿀 때는 새 컨트롤러가 먼저 붙어 구독이 끊기지 않는다.
final _trackSubscriptionProvider = Provider.autoDispose.family<void, String>((ref, trackId) {
  final hub = ref.watch(rankingHubClientProvider);
  unawaited(_guarded('구독', () => hub.subscribeTrack(trackId)));
  ref.onDispose(() => unawaited(_guarded('구독 해제', () => hub.unsubscribeTrack(trackId))));
});

/// 허브 연결 실패는 REST 조회를 막지 않는다. 실패는 로그로 남기고 다음 조회에서 다시 시도된다.
Future<void> _guarded(String what, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    debugPrint('랭킹 허브 $what 실패: $e');
  }
}

/// 트랙·기간별 랭킹. REST 초기 로드 후 RankingHub를 구독해 `RankingUpdated`를 반영한다(05 §3).
///
/// - 월별 조회: 같은 트랙의 허브 스냅샷을 그대로 반영한다.
/// - 일·연 조회: 허브는 월별만 보내므로, 같은 트랙의 갱신 신호가 오면 REST로 다시 읽는다.
/// 화면을 떠나면(autoDispose) 스트림 취소 + 구독 해제.
class RankingController extends AutoDisposeFamilyAsyncNotifier<RankingSnapshot, RankingQuery> {
  @override
  Future<RankingSnapshot> build(RankingQuery arg) async {
    final hub = ref.watch(rankingHubClientProvider);
    final repo = ref.watch(rankingRepositoryProvider);
    var disposed = false;
    ref.onDispose(() => disposed = true);

    ref.watch(_trackSubscriptionProvider(arg.trackId));

    Future<void> reload() async {
      try {
        final fresh = await repo.getRanking(arg.trackId, period: arg.period);
        if (!disposed) {
          state = AsyncData(fresh);
        }
      } catch (e) {
        // 백그라운드 갱신 실패 시 화면의 기존 랭킹은 그대로 둔다.
        debugPrint('랭킹 재조회 실패($arg): $e');
      }
    }

    final sub = hub.rankingUpdated.listen((raw) {
      if (shouldApplyHubSnapshot(arg, raw)) {
        state = AsyncData(RankingSnapshot.fromJson(raw));
      } else if (raw['trackId'] == arg.trackId) {
        unawaited(reload());
      }
    });
    ref.onDispose(sub.cancel);

    // 초기 스냅샷은 REST로 로드(놓친 이벤트 보정, 05 §5).
    return repo.getRanking(arg.trackId, period: arg.period);
  }
}

final rankingControllerProvider =
    AsyncNotifierProvider.autoDispose.family<RankingController, RankingSnapshot, RankingQuery>(
  RankingController.new,
);
