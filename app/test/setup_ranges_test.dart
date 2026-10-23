import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/sessions/domain/setup_ranges.dart';

void main() {
  // F1Laps 셋업 페이지의 막대 폭(%)과 같은 비율인지(값·폭 쌍은 실제 페이지에서 확인).
  const cases = <(String, String, double)>[
    ('Front Wing', '23', 0.46),
    ('Rear Wing Aero', '38', 0.76),
    ('Differential Adjustment On Throttle', '90%', 0.89),
    ('Differential Adjustment Off Throttle', '25%', 0.17),
    ('Front Camber', '-3.40˚', 0.10),
    ('Rear Camber', '-2.00˚', 0.13),
    ('Rear Toe-In', '0.10˚', 0.20),
    ('Front Suspension', '36', 0.875),
    ('Front Anti-Roll Bar', '8', 0.35),
    ('Front Ride Height', '25', 0.50),
    ('Rear Ride Height', '52', 0.20),
    ('Break Pressure', '98', 0.90),
    ('Front Right Tyre Pressure', '29.5', 1.0),
    ('Rear Left Tyre Pressure', '20.5 psi', 0.0),
  ];

  for (final (label, value, expected) in cases) {
    test('$label $value → ${(expected * 100).round()}%', () {
      expect(setupBarFraction(label, value), closeTo(expected, 0.01));
    });
  }

  test('브레이크 바이어스는 값이 클수록 길다(F1Laps의 거꾸로 막대를 따르지 않는다)', () {
    expect(setupBarFraction('Front Brake Bias', '54%'), closeTo(0.2, 0.01));
  });

  test('범위를 모르는 항목·숫자가 아닌 값은 막대가 없다', () {
    expect(setupBarFraction('Engine Braking', '50%'), isNull);
    expect(setupBarFraction('Front Wing', '-'), isNull);
  });

  test('범위 밖 값은 0~1로 자른다', () {
    expect(setupBarFraction('Front Wing', '80'), 1.0);
    expect(setupBarFraction('Rear Ride Height', '10'), 0.0);
  });
}
