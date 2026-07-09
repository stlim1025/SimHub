import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/ranking_hub_client.dart';
import '../data/ranking_repository.dart';
import '../domain/ranking_models.dart';

/// 트랙 마스터 목록.
final tracksProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(rankingRepositoryProvider).getTracks(),
);

/// 트랙별 실시간 랭킹. REST 초기 로드 후 RankingHub를 구독해 RankingUpdated를 즉시 반영(05 §3).
/// 페이지 이탈 시 구독 해제 + 스트림 취소(onDispose).
class RankingController extends FamilyAsyncNotifier<RankingSnapshot, String> {
  @override
  Future<RankingSnapshot> build(String trackId) async {
    final hub = ref.watch(rankingHubClientProvider);

    final sub = hub.rankingUpdated.listen((raw) {
      if (raw['trackId'] == trackId) {
        state = AsyncData(RankingSnapshot.fromJson(raw));
      }
    });
    ref.onDispose(sub.cancel);

    // 관심 트랙 구독(재접속 시 자동 재구독은 Hub 클라이언트가 처리).
    await hub.subscribeTrack(trackId);
    ref.onDispose(() => hub.unsubscribeTrack(trackId));

    // 초기 스냅샷은 REST로 로드(놓친 이벤트 보정, 05 §5).
    return ref.watch(rankingRepositoryProvider).getRanking(trackId);
  }
}

final rankingControllerProvider =
    AsyncNotifierProvider.family<RankingController, RankingSnapshot, String>(
  RankingController.new,
);
