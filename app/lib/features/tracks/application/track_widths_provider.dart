import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/track_width_profile.dart';

/// 실측 트랙 폭 asset 경로.
const String kTrackWidthsAsset = 'assets/track_widths/track_widths.json';

/// 트랙 이름 → 실측 서킷(앱에 들어 있는 asset을 한 번 읽는다). 읽지 못하면 빈 맵(주행 기록으로 추정한 모양을 쓴다).
final trackWidthsProvider = FutureProvider<Map<String, TrackWidthProfile>>((ref) async {
  try {
    final text = await rootBundle.loadString(kTrackWidthsAsset);
    return parseTrackWidths(jsonDecode(text) as Map<String, dynamic>);
  } on Exception {
    return const {};
  }
});
