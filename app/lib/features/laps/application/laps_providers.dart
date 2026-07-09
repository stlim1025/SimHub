import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/laps_repository.dart';
import '../domain/lap_models.dart';

/// 내 랩 기록(트랙 지정 시 개인 최고 포함). trackId=null → 전체 트랙.
final myLapsProvider = FutureProvider.family<MyLaps, String?>(
  (ref, trackId) => ref.watch(lapsRepositoryProvider).getMyLaps(trackId: trackId),
);
