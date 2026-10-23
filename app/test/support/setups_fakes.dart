import 'package:simcenter_app/core/network/api_exception.dart';
import 'package:simcenter_app/features/sessions/domain/setup_display.dart';
import 'package:simcenter_app/features/setups/data/setups_repository.dart';
import 'package:simcenter_app/features/setups/domain/setup_models.dart';
import 'package:simcenter_app/features/tracks/data/tracks_repository.dart';
import 'package:simcenter_app/features/tracks/domain/track_overview_models.dart';
import 'package:simcenter_app/features/tracks/domain/track_sample_geometry.dart';

/// 셋업 모음 저장소(메모리). 요청을 기록한다. [lists]에 없는 트랙은 빈 목록, [details]에 없는 셋업은 404.
class FakeSetupsRepository implements SetupsRepository {
  FakeSetupsRepository({this.tracks = const [], this.lists = const {}, this.details = const {}, this.error});

  final List<SetupTrackSummary> tracks;

  /// 키: `{trackId}|{condition}`.
  final Map<String, SetupList> lists;
  final Map<String, SetupDetail> details;

  /// 있으면 모든 호출이 이 오류로 실패한다.
  final Object? error;
  final trackRequests = <String>[];
  final listRequests = <({String trackId, String condition})>[];
  final detailRequests = <String>[];

  @override
  Future<List<SetupTrackSummary>> getTracks({required String gameCode}) async {
    trackRequests.add(gameCode);
    if (error case final e?) throw e;
    return tracks;
  }

  @override
  Future<SetupList> getSetups({required String trackId, required String condition}) async {
    listRequests.add((trackId: trackId, condition: condition));
    if (error case final e?) throw e;
    return lists['$trackId|$condition'] ??
        SetupList(track: SetupTrackRef(trackId: trackId, name: 'Australia'), condition: condition, items: const []);
  }

  @override
  Future<SetupDetail> getSetup(String setupId) async {
    detailRequests.add(setupId);
    if (error case final e?) throw e;
    final detail = details[setupId];
    if (detail == null) {
      throw ApiException('없음', statusCode: 404);
    }
    return detail;
  }
}

/// 트랙 개요 저장소(메모리). [overviews]에 없는 트랙은 404.
class FakeTracksRepository implements TracksRepository {
  FakeTracksRepository({this.overviews = const {}});

  final Map<String, TrackOverview> overviews;
  final requests = <String>[];

  @override
  Future<TrackOverview> getOverview(String trackId) async {
    requests.add(trackId);
    final overview = overviews[trackId];
    if (overview == null) {
      throw ApiException('없음', statusCode: 404);
    }
    return overview;
  }

  @override
  Future<TrackSampleGeometry?> getGeometry(String trackId, String gameCode) async => null;
}

SetupTrackSummary setupTrackOf(
  String id,
  String name, {
  int displayOrder = 1,
  String? countryCode = 'AU',
  String? circuitName,
  int dryCount = 10,
  int wetCount = 0,
}) =>
    SetupTrackSummary(
      trackId: id,
      name: name,
      displayOrder: displayOrder,
      countryCode: countryCode,
      circuitName: circuitName,
      dryCount: dryCount,
      wetCount: wetCount,
    );

const SetupTrackRef australiaRef = SetupTrackRef(
  trackId: 'au',
  name: 'Australia',
  countryCode: 'AU',
  circuitName: 'Melbourne Grand Prix Circuit',
);

SetupListItem setupItemOf(String id, int rank, {String? team = 'Aston Martin'}) =>
    SetupListItem(
      id: id,
      rank: rank,
      teamName: team,
      sessionType: 'Time Trial',
      lapTimeMs: 75974 + rank,
      sourceUrl: 'https://www.f1laps.com/f1-25/setups/australia/$id/',
    );

SetupDetail setupDetailOf(
  String id, {
  String condition = 'Dry',
  List<SetupGroup> sections = const [
    (title: 'Aerodynamics', items: [(label: 'Front Wing', value: '23'), (label: 'Rear Wing', value: '21')]),
    (title: 'Brakes', items: [(label: 'Brake Pressure', value: '100%')]),
  ],
}) =>
    SetupDetail(
      id: id,
      rank: 1,
      gameCode: 'F1_25',
      track: australiaRef,
      condition: condition,
      teamName: 'Aston Martin',
      sessionType: 'Time Trial',
      lapTimeMs: 75974,
      steering: 'Wheel',
      setOn: DateTime(2025, 12, 22),
      sourceUrl: 'https://www.f1laps.com/f1-25/setups/australia/$id/',
      fetchedAt: DateTime.utc(2026, 10, 22, 9),
      sections: sections,
    );

TrackOverview trackOverviewOf({
  String? mapLapId,
  List<TrackTopLap> top = const [],
  List<TrackBestLap> best = const [],
  TrackMyStats stats = const TrackMyStats(
    lapCount: 42,
    sessionCount: 5,
    bestLapMs: 77101,
    bestTimeTrialLapMs: 77323,
    averageLapMs: 86500,
    averageAiDifficulty: 82.4,
  ),
}) =>
    TrackOverview(
      track: const TrackInfo(
        trackId: 'au',
        name: 'Australia',
        gameCode: 'F1_26',
        countryCode: 'AU',
        circuitName: 'Melbourne Grand Prix Circuit',
        grandPrixName: 'Formula 1 Australian Grand Prix',
        lengthKm: 5.278,
        f1LapRecord: '1:19.813',
      ),
      myStats: stats,
      topTimeTrial: top,
      myBestLaps: best,
      mapLapId: mapLapId,
    );
