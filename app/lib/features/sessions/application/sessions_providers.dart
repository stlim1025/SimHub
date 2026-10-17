import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sessions_repository.dart';
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

/// 세션 목록 한 페이지([kSessionsPageSize]개씩).
final sessionsProvider = FutureProvider.autoDispose.family<SessionsPage, SessionsQuery>(
  (ref, query) => ref.watch(sessionsRepositoryProvider).getMySessions(
        sessionType: sessionTypeForFilter(query.filter),
        page: query.page,
        pageSize: kSessionsPageSize,
      ),
);

/// 세션 하나의 상세. 화면을 다시 열면 새로 불러온다.
final sessionDetailProvider = FutureProvider.autoDispose.family<SessionDetail, String>(
  (ref, sessionId) => ref.watch(sessionsRepositoryProvider).getMySession(sessionId),
);
