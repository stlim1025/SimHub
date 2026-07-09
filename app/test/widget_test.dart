import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/util/lap_time.dart';

void main() {
  group('formatLapTime', () {
    test('밀리초를 m:ss.mmm로 표기', () {
      expect(formatLapTime(83452), '1:23.452');
      expect(formatLapTime(60000), '1:00.000');
      expect(formatLapTime(9999), '0:09.999');
      expect(formatLapTime(0), '0:00.000');
    });

    test('음수는 플레이스홀더', () {
      expect(formatLapTime(-1), '--:--.---');
    });
  });
}
