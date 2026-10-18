import 'package:flutter/material.dart';

import 'track_laps_view.dart';

/// 고른 트랙의 내 랩 표(`/laps/tracks/:trackId`, D-47). 본문은 `/laps`와 같은 [TrackLapsView]다.
class TrackLapsPage extends StatelessWidget {
  const TrackLapsPage({super.key, required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context) => TrackLapsView(trackId: trackId);
}
