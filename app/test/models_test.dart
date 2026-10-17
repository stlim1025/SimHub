import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/auth/domain/auth_models.dart';
import 'package:simcenter_app/features/devices/domain/device_models.dart';
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

  test('MyTrack.fromJson (bestValidLapTimeMs 허용 + lastSetAt 파싱)', () {
    final t = MyTrack.fromJson({
      'trackId': 't1',
      'trackName': 'Silverstone',
      'gameCode': 'F1_25',
      'lapCount': 12,
      'bestValidLapTimeMs': 83452,
      'lastSetAt': '2026-10-12T09:03:21Z',
    });
    expect(t.trackId, 't1');
    expect(t.trackName, 'Silverstone');
    expect(t.gameCode, 'F1_25');
    expect(t.lapCount, 12);
    expect(t.bestValidLapTimeMs, 83452);
    expect(t.lastSetAt, DateTime.utc(2026, 10, 12, 9, 3, 21));
    expect(t.lastSetAt.isUtc, true);
  });

  test('MyTrack.fromJson (유효 랩이 없으면 bestValidLapTimeMs가 null)', () {
    final t = MyTrack.fromJson({
      'trackId': 't2',
      'trackName': 'Monaco',
      'gameCode': 'F1_25',
      'lapCount': 1,
      'bestValidLapTimeMs': null,
      'lastSetAt': '2026-10-13T00:00:00Z',
    });
    expect(t.bestValidLapTimeMs, isNull);
    expect(t.lapCount, 1);
  });

  test('AgentDevice.fromJson (lastSeenAt 파싱)', () {
    final d = AgentDevice.fromJson({
      'deviceId': 'd1',
      'name': 'RIG-PC',
      'lastSeenAt': '2026-10-17T11:55:00Z',
      'createdAt': '2026-10-01T09:00:00Z',
    });
    expect(d.deviceId, 'd1');
    expect(d.name, 'RIG-PC');
    expect(d.lastSeenAt, DateTime.utc(2026, 10, 17, 11, 55));
    expect(d.createdAt, DateTime.utc(2026, 10, 1, 9));
    expect(d.createdAt.isUtc, true);
  });

  test('AgentDevice.fromJson (lastSeenAt이 null이면 null)', () {
    final d = AgentDevice.fromJson({
      'deviceId': 'd2',
      'name': 'LAPTOP',
      'lastSeenAt': null,
      'createdAt': '2026-10-01T09:00:00Z',
    });
    expect(d.lastSeenAt, isNull);
  });

  test('PairingCode.fromJson', () {
    final c = PairingCode.fromJson({'code': 'K7F2-9QXM', 'expiresAt': '2026-10-17T12:10:00Z'});
    expect(c.code, 'K7F2-9QXM');
    expect(c.expiresAt, DateTime.utc(2026, 10, 17, 12, 10));
    expect(c.expiresAt.isUtc, true);
  });

  test('Track.fromJson', () {
    final t = Track.fromJson({'trackId': 't1', 'gameCode': 'F1_25', 'name': 'Monaco'});
    expect(t.name, 'Monaco');
  });
}
