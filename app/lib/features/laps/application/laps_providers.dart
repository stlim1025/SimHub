import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/laps_repository.dart';
import '../domain/lap_models.dart';

/// 트랙별 랩 표의 한 페이지 크기(docs/11 §7.3).
const int kTrackLapsPageSize = 15;

/// 내 랩이 있는 트랙 목록(마지막 주행 순). 화면을 다시 열면 새로 불러온다.
final myTracksProvider = FutureProvider.autoDispose<List<MyTrack>>(
  (ref) => ref.watch(lapsRepositoryProvider).getMyTracks(),
);

/// 트랙별 랩 조회 조건(트랙 + 정렬 + 유효 랩만 + 페이지). 값 동등성으로 provider family 키가 된다.
@immutable
class TrackLapsQuery {
  const TrackLapsQuery({
    required this.trackId,
    this.sort = kLapSortRecent,
    this.validOnly = false,
    this.page = 1,
  });

  final String trackId;
  final String sort;

  /// 유효 랩만(docs/15 §2.1 "유효 랩만").
  final bool validOnly;

  /// 1부터 시작.
  final int page;

  @override
  bool operator ==(Object other) =>
      other is TrackLapsQuery &&
      other.trackId == trackId &&
      other.sort == sort &&
      other.validOnly == validOnly &&
      other.page == page;

  @override
  int get hashCode => Object.hash(trackId, sort, validOnly, page);

  @override
  String toString() => 'TrackLapsQuery($trackId, $sort, validOnly: $validOnly, $page)';
}

/// 한 트랙의 내 랩 한 페이지([kTrackLapsPageSize]개씩).
final trackLapsProvider = FutureProvider.autoDispose.family<MyLaps, TrackLapsQuery>(
  (ref, query) => ref.watch(lapsRepositoryProvider).getMyLaps(
        trackId: query.trackId,
        sort: query.sort,
        validOnly: query.validOnly,
        page: query.page,
        pageSize: kTrackLapsPageSize,
      ),
);
