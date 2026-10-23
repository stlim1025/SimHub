import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../laps/data/laps_repository.dart';
import '../../laps/domain/lap_models.dart';
import '../data/lap_detail_repository.dart';
import '../data/public_lap_repository.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_detail_models.dart';
import '../domain/shared_lap.dart';

/// Your Best Laps 탭이 보여 주는 랩 수(docs/15 §2.3).
const int kBestLapsCount = 10;

/// 랩 하나의 상세(+ 고른 비교 대상, D-51). 화면을 다시 열면 새로 불러온다.
final lapDetailProvider = FutureProvider.autoDispose.family<LapDetail, LapDetailKey>(
  (ref, key) => ref.watch(lapDetailRepositoryProvider).getLapDetail(key.lapId, compare: key.selection),
);

/// 랩 하나의 텔레메트리 트레이스. 저장되지 않았으면(404) null.
final lapTraceProvider = FutureProvider.autoDispose.family<LapTrace?, String>(
  (ref, lapId) => ref.watch(lapDetailRepositoryProvider).getLapTrace(lapId),
);

/// 같은 세션의 다른 차 베스트 랩 트레이스(모든 차 표본으로 복원). 없으면 null.
final fieldLapTraceProvider = FutureProvider.autoDispose.family<LapTrace?, ({String sessionId, int carIndex})>(
  (ref, key) => ref.watch(lapDetailRepositoryProvider).getFieldLapTrace(key.sessionId, key.carIndex),
);

/// 비교 랩 트레이스(남의 공개 랩 포함, D-51). 없거나 볼 수 없으면 null.
final comparisonTraceProvider = FutureProvider.autoDispose.family<LapTrace?, String>(
  (ref, lapId) => ref.watch(lapDetailRepositoryProvider).getComparisonTrace(lapId),
);

/// 공유 링크로 보는 랩(로그인 없음) + 주소의 비교 랩(있으면).
final sharedLapProvider = FutureProvider.autoDispose.family<SharedLap, SharedLapKey>(
  (ref, key) => ref.watch(publicLapRepositoryProvider).getLap(key.lapId, compareLapId: key.compareLapId),
);

/// 공유 링크로 보는 랩의 트레이스. 저장되지 않았으면(404) null.
final sharedLapTraceProvider = FutureProvider.autoDispose.family<LapTrace?, String>(
  (ref, lapId) => ref.watch(publicLapRepositoryProvider).getTrace(lapId),
);

/// Share 버튼이 쓰는 지금 주소의 바탕(웹 = 브라우저 주소). 테스트에서 바꾼다.
final shareBaseUriProvider = Provider<Uri>((ref) => Uri.base);

/// 한 트랙의 내 유효 랩 빠른 순 [kBestLapsCount]개(`sort=fastest&validOnly=true&pageSize=10`).
final bestLapsProvider = FutureProvider.autoDispose.family<MyLaps, String>(
  (ref, trackId) => ref.watch(lapsRepositoryProvider).getMyLaps(
        trackId: trackId,
        sort: kLapSortFastest,
        validOnly: true,
        pageSize: kBestLapsCount,
      ),
);
