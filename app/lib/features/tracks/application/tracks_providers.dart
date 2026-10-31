import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tracks_repository.dart';
import '../domain/track_overview_models.dart';
import '../domain/track_sample_geometry.dart';
import 'track_corners_provider.dart';
import 'track_widths_provider.dart';

/// 트랙 하나의 개요. 화면을 다시 열면 새로 불러온다.
/// 트랙·게임의 표본 트랙 형상. 표본이 없으면 null(다시보기는 실측·추정 모양을 쓴다).
final trackGeometryProvider = FutureProvider.autoDispose.family<TrackSampleGeometry?, ({String trackId, String gameCode})>(
  (ref, key) => ref.watch(tracksRepositoryProvider).getGeometry(key.trackId, key.gameCode),
);

final trackOverviewProvider = FutureProvider.autoDispose.family<TrackOverview, String>(
  (ref, trackId) => ref.watch(tracksRepositoryProvider).getOverview(trackId),
);

/// 다시보기 서킷 재료(실측 트랙 폭·표본 트랙 형상·공식 코너)가 아직 오는 중인지. 다 온 뒤에 다시보기를 띄워야
/// 대략 그린 서킷이 먼저 떴다가 바뀌지 않는다(실패한 재료는 기다리지 않고 없는 대로 그린다).
bool watchReplayCircuitLoading(WidgetRef ref, {required String trackId, required String gameCode}) {
  final widths = ref.watch(trackWidthsProvider);
  final geometry = ref.watch(trackGeometryProvider((trackId: trackId, gameCode: gameCode)));
  final corners = ref.watch(trackCornersProvider);
  return widths.isLoading || geometry.isLoading || corners.isLoading;
}
