import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/track_outline.dart';

/// 서킷 윤곽 asset 경로.
const String kTrackOutlinesAsset = 'assets/track_outlines/track_outlines.json';

/// 트랙 이름 → 서킷 윤곽(앱에 들어 있는 asset을 한 번 읽는다). 읽지 못하면 빈 맵(그림 없이).
final trackOutlinesProvider = FutureProvider<Map<String, TrackOutline>>((ref) async {
  try {
    final text = await rootBundle.loadString(kTrackOutlinesAsset);
    return parseTrackOutlines(jsonDecode(text) as Map<String, dynamic>);
  } on Exception {
    return const {};
  }
});
