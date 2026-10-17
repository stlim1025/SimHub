import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../laps/data/laps_repository.dart';
import '../../laps/domain/lap_models.dart';

/// Dashboard에 보여줄 최근 랩 개수.
const int kRecentLapCount = 5;

/// 내 최근 랩(최신순 [kRecentLapCount]개).
final recentLapsProvider = FutureProvider.autoDispose<MyLaps>(
  (ref) => ref.watch(lapsRepositoryProvider).getMyLaps(pageSize: kRecentLapCount),
);
