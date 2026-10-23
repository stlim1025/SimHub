/// 셋업 값의 게임 범위(F1 25/26 셋업 화면의 최솟값~최댓값). 셋업 화면의 막대가 값이 범위의 어디쯤인지 보여 준다.
/// F1Laps 셋업 페이지의 막대 폭과 같은 범위다(브레이크 바이어스만 F1Laps는 거꾸로 그려, 여기서는 다른 항목처럼 값이 클수록 길다).
class SetupRange {
  const SetupRange(this.min, this.max);

  final double min;
  final double max;

  /// [value]가 범위에서 차지하는 비율(0~1로 자른다).
  double fractionOf(double value) {
    final span = max - min;
    if (span <= 0) {
      return 0;
    }
    return ((value - min) / span).clamp(0.0, 1.0);
  }
}

const SetupRange _wing = SetupRange(0, 50);
const SetupRange _differential = SetupRange(10, 100);
const SetupRange _frontCamber = SetupRange(-3.5, -2.5);
const SetupRange _rearCamber = SetupRange(-2.2, -0.7);
const SetupRange _toe = SetupRange(0, 0.5);
const SetupRange _suspension = SetupRange(1, 41);
const SetupRange _antiRollBar = SetupRange(1, 21);
const SetupRange _frontRideHeight = SetupRange(10, 40);
const SetupRange _rearRideHeight = SetupRange(40, 100);
const SetupRange _brakePressure = SetupRange(80, 100);
const SetupRange _brakeBias = SetupRange(50, 70);
const SetupRange _frontTyrePressure = SetupRange(22.5, 29.5);
const SetupRange _rearTyrePressure = SetupRange(20.5, 26.5);

/// 정규화한 이름표(소문자·영문자만) → 범위. 우리 셋업 이름표와 F1Laps 이름표(오타 "Break" 포함)를 모두 받는다.
const Map<String, SetupRange> _rangesByLabel = {
  'frontwing': _wing,
  'frontwingaero': _wing,
  'rearwing': _wing,
  'rearwingaero': _wing,
  'differentialadjustmentonthrottle': _differential,
  'differentialadjustmentoffthrottle': _differential,
  'differentialonthrottle': _differential,
  'differentialoffthrottle': _differential,
  'frontcamber': _frontCamber,
  'rearcamber': _rearCamber,
  'fronttoe': _toe,
  'fronttoeout': _toe,
  'reartoe': _toe,
  'reartoein': _toe,
  'frontsuspension': _suspension,
  'rearsuspension': _suspension,
  'frontantirollbar': _antiRollBar,
  'rearantirollbar': _antiRollBar,
  'frontrideheight': _frontRideHeight,
  'rearrideheight': _rearRideHeight,
  'brakepressure': _brakePressure,
  'breakpressure': _brakePressure,
  'frontbrakebias': _brakeBias,
  'frontbreakbias': _brakeBias,
  'frontlefttyrepressure': _frontTyrePressure,
  'frontrighttyrepressure': _frontTyrePressure,
  'rearlefttyrepressure': _rearTyrePressure,
  'rearrighttyrepressure': _rearTyrePressure,
};

final RegExp _nonLetters = RegExp('[^a-z]');
final RegExp _number = RegExp(r'-?\d+(?:\.\d+)?');

/// 이름표 → 범위. 모르는 항목(엔진 브레이킹·연료 등)은 null(막대 없이 값만).
SetupRange? setupRangeOf(String label) => _rangesByLabel[label.toLowerCase().replaceAll(_nonLetters, '')];

/// 표시 값("-3.50˚", "90%", "23.5 psi")의 첫 숫자. 숫자가 없으면 null.
double? setupNumberOf(String value) {
  final match = _number.firstMatch(value);
  return match == null ? null : double.tryParse(match.group(0)!);
}

/// 이름표·표시 값 → 막대 비율(0~1). 범위를 모르거나 숫자가 아니면 null.
double? setupBarFraction(String label, String value) {
  final range = setupRangeOf(label);
  final number = setupNumberOf(value);
  if (range == null || number == null) {
    return null;
  }
  return range.fractionOf(number);
}
