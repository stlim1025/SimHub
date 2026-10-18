import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/widgets/track_picker.dart';
import 'package:simcenter_app/features/laps/presentation/laps_track_picker.dart';
import 'package:simcenter_app/features/ranking/domain/ranking_models.dart';

import 'support/fakes.dart';

const _master = [
  Track(trackId: 't0', gameCode: 'F1_25', name: 'Melbourne', countryCode: 'AU', displayOrder: 1),
  Track(trackId: 't1', gameCode: 'F1_25', name: 'Jeddah', countryCode: 'SA', displayOrder: 5),
];

void main() {
  group('lapsTrackChoices', () {
    test('트랙 마스터가 있으면 그 순서(캘린더 순서) 그대로', () {
      final choices = lapsTrackChoices(_master, [trackOf('t1', 'Jeddah')]);

      expect(choices.map((c) => c.id), ['t0', 't1']);
      expect(choices.first.countryCode, 'AU');
    });

    test('트랙 마스터가 없거나 비었으면 내 트랙(마지막 주행 순)으로 대신한다', () {
      final mine = [trackOf('t9', 'Portimão', countryCode: 'PT'), trackOf('t1', 'Jeddah')];

      expect(lapsTrackChoices(null, mine).map((c) => c.id), ['t9', 't1']);
      expect(lapsTrackChoices(const [], mine).first.countryCode, 'PT');
      expect(lapsTrackChoices(null, null), isEmpty);
    });
  });

  group('resolveLapsTrack', () {
    test('트랙 마스터 → 내 트랙 → 랩의 트랙 이름(국기 없음) 순으로 찾는다', () {
      expect(
        resolveLapsTrack(trackId: 't1', master: _master, mine: null),
        const TrackChoice(id: 't1', name: 'Jeddah', countryCode: 'SA'),
      );
      expect(
        resolveLapsTrack(trackId: 't9', master: _master, mine: [trackOf('t9', 'Portimão', countryCode: 'PT')]),
        const TrackChoice(id: 't9', name: 'Portimão', countryCode: 'PT'),
      );
      expect(
        resolveLapsTrack(trackId: 't8', master: _master, mine: const [], fallbackName: 'Hockenheim'),
        const TrackChoice(id: 't8', name: 'Hockenheim'),
      );
    });

    test('트랙이 없거나 어디서도 찾지 못하면 null(자리표시 제목)', () {
      expect(resolveLapsTrack(trackId: null, master: _master, mine: null), isNull);
      expect(resolveLapsTrack(trackId: 'nope', master: _master, mine: null), isNull);
    });
  });
}
