import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/util/relative_time.dart';

void main() {
  group('formatRemaining', () {
    test('formatRemaining_ZeroOrNegative_IsExpired', () {
      expect(formatRemaining(const Duration(minutes: 9, seconds: 59)), '9:59');
      expect(formatRemaining(Duration.zero), '만료됨');
      expect(formatRemaining(const Duration(seconds: -3)), '만료됨');
    });

    test('초는 두 자리로 채운다', () {
      expect(formatRemaining(const Duration(minutes: 10)), '10:00');
      expect(formatRemaining(const Duration(minutes: 1, seconds: 5)), '1:05');
      expect(formatRemaining(const Duration(seconds: 59)), '0:59');
    });

    test('1초 미만 남았으면 만료가 아니라 0:01로 올림한다', () {
      expect(formatRemaining(const Duration(milliseconds: 400)), '0:01');
      expect(formatRemaining(const Duration(minutes: 9, seconds: 58, milliseconds: 100)), '9:59');
    });
  });

  group('describeAgo', () {
    test('describeAgo', () {
      expect(describeAgo(const Duration(minutes: 5)), '5분 전');
      expect(describeAgo(const Duration(hours: 3)), '3시간 전');
      expect(describeAgo(const Duration(days: 82)), '82일 전');
    });

    test('단위 경계에서 큰 단위로 넘어간다', () {
      expect(describeAgo(const Duration(minutes: 59, seconds: 59)), '59분 전');
      expect(describeAgo(const Duration(minutes: 60)), '1시간 전');
      expect(describeAgo(const Duration(hours: 23, minutes: 59)), '23시간 전');
      expect(describeAgo(const Duration(hours: 24)), '1일 전');
    });

    test('1분 미만이거나 음수(시계 오차)면 방금 전', () {
      expect(describeAgo(const Duration(seconds: 30)), '방금 전');
      expect(describeAgo(const Duration(seconds: -5)), '방금 전');
    });
  });
}
