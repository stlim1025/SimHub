import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/selected_game_provider.dart';
import '../data/sessions_repository.dart';
import '../domain/race_analysis.dart';
import '../domain/race_highlights.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';

/// 세션 목록 조회 조건(필터 + 페이지). 값 동등성으로 provider family 키가 된다.
@immutable
class SessionsQuery {
  const SessionsQuery(this.filter, this.page);

  /// `all`·`race`·`qualifying`·`practice`(`normalizeSessionFilter`를 거친 값).
  final String filter;

  /// 1부터 시작.
  final int page;

  @override
  bool operator ==(Object other) =>
      other is SessionsQuery && other.filter == filter && other.page == page;

  @override
  int get hashCode => Object.hash(filter, page);

  @override
  String toString() => 'SessionsQuery($filter, $page)';
}

/// 세션 목록 한 페이지([kSessionsPageSize]개씩, 선택한 게임만).
final sessionsProvider = FutureProvider.autoDispose.family<SessionSummaryPage, SessionsQuery>(
  (ref, query) => ref.watch(sessionsRepositoryProvider).getMySessions(
        sessionType: sessionTypeForFilter(query.filter),
        page: query.page,
        pageSize: kSessionsPageSize,
        gameCode: ref.watch(selectedGameProvider),
      ),
);

/// 세션 하나의 상세. 화면을 다시 열면 새로 불러온다.
final sessionDetailProvider = FutureProvider.autoDispose.family<SessionDetail, String>(
  (ref, sessionId) => ref.watch(sessionsRepositoryProvider).getMySession(sessionId),
);

/// 레이스 세션 하나의 하이라이트.
final raceHighlightsProvider = FutureProvider.autoDispose.family<RaceHighlights, String>(
  (ref, sessionId) => ref.watch(sessionsRepositoryProvider).getHighlights(sessionId),
);

/// 레이스 세션 하나의 심층 분석(Race Review 탭을 열 때 읽는다).
final raceAnalysisProvider = FutureProvider.autoDispose.family<RaceAnalysis, String>(
  (ref, sessionId) => ref.watch(sessionsRepositoryProvider).getRaceAnalysis(sessionId),
);
