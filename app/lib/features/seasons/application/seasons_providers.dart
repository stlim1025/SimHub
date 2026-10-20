import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/selected_game_provider.dart';
import '../data/seasons_repository.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';

/// 내 시즌 전부(선택한 게임만, 서버 정렬 = 마지막 세션 시각 내림차순). [kSeasonsPageSize]개씩 끝 페이지까지 이어 읽는다.
/// `/seasons` 진입 시 열 시즌 고르기와 시즌 메뉴(진행 중·완료 묶음)가 쓴다.
final allSeasonsProvider = FutureProvider.autoDispose<List<SeasonSummary>>((ref) async {
  final repo = ref.watch(seasonsRepositoryProvider);
  final gameCode = ref.watch(selectedGameProvider);
  final seasons = <SeasonSummary>[];
  for (var page = 1;; page++) {
    final result = await repo.getMySeasons(page: page, pageSize: kSeasonsPageSize, gameCode: gameCode);
    seasons.addAll(result.items);
    if (result.items.isEmpty || seasons.length >= result.total) {
      return seasons;
    }
  }
});

/// 시즌 하나의 상세(라운드 + Standings). 세 탭이 같은 스냅샷을 쓰고, 화면을 다시 열면 새로 불러온다.
final seasonDetailProvider = FutureProvider.autoDispose.family<SeasonDetail, String>(
  (ref, seasonId) => ref.watch(seasonsRepositoryProvider).getMySeason(seasonId),
);
