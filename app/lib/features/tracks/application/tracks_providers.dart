import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tracks_repository.dart';
import '../domain/track_overview_models.dart';
import '../domain/track_sample_geometry.dart';

/// 트랙 하나의 개요. 화면을 다시 열면 새로 불러온다.
/// 트랙·게임의 표본 트랙 형상. 표본이 없으면 null(다시보기는 실측·추정 모양을 쓴다).
final trackGeometryProvider = FutureProvider.autoDispose.family<TrackSampleGeometry?, ({String trackId, String gameCode})>(
  (ref, key) => ref.watch(tracksRepositoryProvider).getGeometry(key.trackId, key.gameCode),
);

final trackOverviewProvider = FutureProvider.autoDispose.family<TrackOverview, String>(
  (ref, trackId) => ref.watch(tracksRepositoryProvider).getOverview(trackId),
);
