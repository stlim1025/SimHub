import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lap_detail/domain/lap_corners.dart';

/// 공식 코너 번호·위치 asset 경로.
const String kTrackCornersAsset = 'assets/track_corners/track_corners.json';

/// 트랙 이름 → 공식 코너(앱에 들어 있는 asset을 한 번 읽는다). 읽지 못하면 빈 맵(주행선에서 코너를 찾는다).
final trackCornersProvider = FutureProvider<Map<String, List<OfficialCorner>>>((ref) async {
  try {
    final text = await rootBundle.loadString(kTrackCornersAsset);
    return parseTrackCorners(jsonDecode(text) as Map<String, dynamic>);
  } on Exception {
    return const {};
  }
});
