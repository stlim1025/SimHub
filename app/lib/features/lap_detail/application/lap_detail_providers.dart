import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../laps/data/laps_repository.dart';
import '../../laps/domain/lap_models.dart';
import '../data/lap_detail_repository.dart';
import '../domain/lap_detail_models.dart';

/// Your Best Laps 탭이 보여 주는 랩 수(docs/15 §2.3).
const int kBestLapsCount = 10;

/// 랩 하나의 상세. 화면을 다시 열면 새로 불러온다.
final lapDetailProvider = FutureProvider.autoDispose.family<LapDetail, String>(
  (ref, lapId) => ref.watch(lapDetailRepositoryProvider).getLapDetail(lapId),
);

/// 랩 하나의 텔레메트리 트레이스. 저장되지 않았으면(404) null.
final lapTraceProvider = FutureProvider.autoDispose.family<LapTrace?, String>(
  (ref, lapId) => ref.watch(lapDetailRepositoryProvider).getLapTrace(lapId),
);

/// 한 트랙의 내 유효 랩 빠른 순 [kBestLapsCount]개(`sort=fastest&validOnly=true&pageSize=10`).
final bestLapsProvider = FutureProvider.autoDispose.family<MyLaps, String>(
  (ref, trackId) => ref.watch(lapsRepositoryProvider).getMyLaps(
        trackId: trackId,
        sort: kLapSortFastest,
        validOnly: true,
        pageSize: kBestLapsCount,
      ),
);
