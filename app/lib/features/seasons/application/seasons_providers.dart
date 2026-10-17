import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seasons_repository.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';

/// 시즌 목록 한 페이지([kSeasonsPageSize]개씩). 키는 1부터 시작하는 페이지 번호.
final seasonsProvider = FutureProvider.autoDispose.family<SeasonSummaryPage, int>(
  (ref, page) => ref.watch(seasonsRepositoryProvider).getMySeasons(page: page, pageSize: kSeasonsPageSize),
);

/// 시즌 하나의 상세(라운드 + Standings). 세 탭이 같은 스냅샷을 쓰고, 화면을 다시 열면 새로 불러온다.
final seasonDetailProvider = FutureProvider.autoDispose.family<SeasonDetail, String>(
  (ref, seasonId) => ref.watch(seasonsRepositoryProvider).getMySeason(seasonId),
);
