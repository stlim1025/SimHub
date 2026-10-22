import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tracks_repository.dart';
import '../domain/track_overview_models.dart';

/// 트랙 하나의 개요. 화면을 다시 열면 새로 불러온다.
final trackOverviewProvider = FutureProvider.autoDispose.family<TrackOverview, String>(
  (ref, trackId) => ref.watch(tracksRepositoryProvider).getOverview(trackId),
);
