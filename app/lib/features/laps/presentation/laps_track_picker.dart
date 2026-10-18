import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/track_picker.dart';
import '../../ranking/application/ranking_providers.dart';
import '../../ranking/domain/ranking_models.dart';
import '../../ranking/presentation/track_choices.dart';
import '../application/laps_providers.dart';
import '../domain/lap_display.dart';
import '../domain/lap_models.dart';

/// 고른 트랙이 없을 때(기록이 하나도 없음)의 제목.
const String _placeholder = 'Laps';

/// 메뉴 항목: 트랙 마스터(`GET /tracks`, 캘린더 순서)가 있으면 그것, 아직 없거나 실패하면 내 트랙(마지막 주행 순).
List<TrackChoice> lapsTrackChoices(List<Track>? master, List<MyTrack>? mine) {
  if (master != null && master.isNotEmpty) {
    return trackChoicesOf(master);
  }
  return [
    for (final track in mine ?? const <MyTrack>[])
      TrackChoice(id: track.trackId, name: track.trackName, countryCode: track.countryCode),
  ];
}

/// 제목에 보일 트랙: 트랙 마스터 → 내 트랙 → 랩의 트랙 이름([fallbackName], 국기 없음) 순으로 찾는다. [trackId]가 null이면 null.
TrackChoice? resolveLapsTrack({
  required String? trackId,
  required List<Track>? master,
  required List<MyTrack>? mine,
  String? fallbackName,
}) {
  if (trackId == null) {
    return null;
  }
  for (final track in master ?? const <Track>[]) {
    if (track.trackId == trackId) {
      return trackChoiceOf(track);
    }
  }
  for (final track in mine ?? const <MyTrack>[]) {
    if (track.trackId == trackId) {
      return TrackChoice(id: track.trackId, name: track.trackName, countryCode: track.countryCode);
    }
  }
  return fallbackName == null ? null : TrackChoice(id: trackId, name: fallbackName);
}

/// Laps 화면의 제목 = 트랙 메뉴(D-47). 고르면 `/laps/tracks/:trackId`로 간다.
class LapsTrackPicker extends ConsumerWidget {
  const LapsTrackPicker({super.key, required this.trackId, this.fallbackName});

  /// 보고 있는 트랙. null이면 자리표시 `Laps`.
  final String? trackId;

  /// 트랙 목록에서 찾지 못할 때 쓸 이름(랩의 트랙 이름).
  final String? fallbackName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final master = ref.watch(tracksProvider).valueOrNull;
    final mine = ref.watch(myTracksProvider).valueOrNull;
    return TrackPicker(
      tracks: lapsTrackChoices(master, mine),
      selected: resolveLapsTrack(trackId: trackId, master: master, mine: mine, fallbackName: fallbackName),
      placeholder: _placeholder,
      onSelected: (choice) => context.go(trackLapsLocation(choice.id)),
    );
  }
}
