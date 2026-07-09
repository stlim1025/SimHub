import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/laps/domain/lap_models.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';

void main() {
  test('LoginResult.fromJson', () {
    final r = LoginResult.fromJson({
      'accessToken': 'jwt',
      'expiresAt': '2026-07-08T10:00:00Z',
      'user': {'userId': 'u1', 'displayName': '홍길동'},
    });
    expect(r.accessToken, 'jwt');
    expect(r.user.displayName, '홍길동');
    expect(r.expiresAt.isUtc, true);
  });

  test('RankingSnapshot.fromJson (계약 필드)', () {
    final s = RankingSnapshot.fromJson({
      'trackId': 't1',
      'trackName': 'Silverstone',
      'gameCode': 'F1_25',
      'period': 'monthly',
      'periodKey': '2026-07',
      'entries': [
        {'rank': 1, 'displayName': '홍길동', 'bestLapTimeMs': 83452, 'setAt': '2026-07-07T09:03:21Z'},
      ],
    });
    expect(s.periodKey, '2026-07');
    expect(s.entries.single.rank, 1);
    expect(s.entries.single.bestLapTimeMs, 83452);
  });

  test('MyLaps.fromJson (personalBest null 허용 + 섹터)', () {
    final m = MyLaps.fromJson({
      'personalBest': null,
      'laps': {
        'page': 1,
        'pageSize': 20,
        'total': 1,
        'items': [
          {
            'lapId': 'l1',
            'trackName': 'Silverstone',
            'gameCode': 'F1_25',
            'sessionType': 'TimeTrial',
            'lapTimeMs': 83452,
            'sectors': [
              {'sectorNumber': 1, 'sectorTimeMs': 27010},
            ],
            'isValid': true,
            'isRankingEligible': true,
            'setAt': '2026-07-07T09:03:21Z',
          },
        ],
      },
    });
    expect(m.personalBest, isNull);
    expect(m.total, 1);
    expect(m.laps.single.sectors.single.sectorTimeMs, 27010);
    expect(m.laps.single.isRankingEligible, true);
  });

  test('Track.fromJson', () {
    final t = Track.fromJson({'trackId': 't1', 'gameCode': 'F1_25', 'name': 'Monaco'});
    expect(t.name, 'Monaco');
  });
}
