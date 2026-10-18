// View Setup 대화상자의 묶음(docs/15 §11.3 Details · Setup). 키는 Agent `F1DetailSections.FromSetup`(D-49)과 같다.

/// 셋업 한 줄.
typedef SetupItem = ({String label, String value});

/// 셋업 묶음(제목 + 줄들).
typedef SetupGroup = ({String title, List<SetupItem> items});

/// 알려진 키 하나: 묶음 · 이름 · 단위.
typedef _SetupKey = ({String group, String label, String unit});

const String _aero = 'Aerodynamics';
const String _transmission = 'Transmission';
const String _geometry = 'Suspension Geometry';
const String _suspension = 'Suspension';
const String _brakes = 'Brakes';
const String _tyres = 'Tyres';
const String _fuel = 'Fuel';
const String _other = 'Other';

/// 묶음 순서(F1 25 셋업 화면 순서).
const List<String> _groupOrder = [_aero, _transmission, _geometry, _suspension, _brakes, _tyres, _fuel, _other];

const String _percent = '%';
const String _degree = '°';
const String _psi = ' psi';
const String _kg = ' kg';
const String _none = '';

const Map<String, _SetupKey> _knownKeys = {
  'frontWing': (group: _aero, label: 'Front Wing Aero', unit: _none),
  'rearWing': (group: _aero, label: 'Rear Wing Aero', unit: _none),
  'onThrottle': (group: _transmission, label: 'Differential On Throttle', unit: _percent),
  'offThrottle': (group: _transmission, label: 'Differential Off Throttle', unit: _percent),
  'engineBraking': (group: _transmission, label: 'Engine Braking', unit: _percent),
  'frontCamber': (group: _geometry, label: 'Front Camber', unit: _degree),
  'rearCamber': (group: _geometry, label: 'Rear Camber', unit: _degree),
  'frontToe': (group: _geometry, label: 'Front Toe-Out', unit: _degree),
  'rearToe': (group: _geometry, label: 'Rear Toe-In', unit: _degree),
  'frontSuspension': (group: _suspension, label: 'Front Suspension', unit: _none),
  'rearSuspension': (group: _suspension, label: 'Rear Suspension', unit: _none),
  'frontAntiRollBar': (group: _suspension, label: 'Front Anti-Roll Bar', unit: _none),
  'rearAntiRollBar': (group: _suspension, label: 'Rear Anti-Roll Bar', unit: _none),
  'frontSuspensionHeight': (group: _suspension, label: 'Front Ride Height', unit: _none),
  'rearSuspensionHeight': (group: _suspension, label: 'Rear Ride Height', unit: _none),
  'brakePressure': (group: _brakes, label: 'Brake Pressure', unit: _percent),
  'brakeBias': (group: _brakes, label: 'Front Brake Bias', unit: _percent),
  'tyrePressureFL': (group: _tyres, label: 'Front Left Tyre Pressure', unit: _psi),
  'tyrePressureFR': (group: _tyres, label: 'Front Right Tyre Pressure', unit: _psi),
  'tyrePressureRL': (group: _tyres, label: 'Rear Left Tyre Pressure', unit: _psi),
  'tyrePressureRR': (group: _tyres, label: 'Rear Right Tyre Pressure', unit: _psi),
  'fuelLoad': (group: _fuel, label: 'Fuel Load', unit: _kg),
  'ballast': (group: _other, label: 'Ballast', unit: _none),
  'nextFrontWingValue': (group: _other, label: 'Next Front Wing', unit: _none),
};

const int _maxFractionDigits = 2;
final RegExp _trailingZeros = RegExp(r'\.?0+$');

/// 값 → 글자. 정수는 그대로, 소수는 둘째 자리까지(끝 0 제거), 참/거짓은 Yes/No(순수 함수).
String formatSetupValue(Object? value, {String unit = _none}) {
  final text = switch (value) {
    final int v => '$v',
    final double v when v == v.roundToDouble() => '${v.toInt()}',
    final double v => v.toStringAsFixed(_maxFractionDigits).replaceFirst(_trailingZeros, ''),
    final bool v => v ? 'Yes' : 'No',
    null => '-',
    _ => '$value',
  };
  return value is num ? '$text$unit' : text;
}

/// 셋업 키·값 → 묶음들(알려진 키는 이름·단위, 모르는 키는 `Other`에 원래 키 그대로). 값이 null인 키와 빈 묶음은 뺀다(순수 함수).
List<SetupGroup> setupGroups(Map<String, Object?> setup) {
  final byGroup = <String, List<SetupItem>>{};
  for (final MapEntry(:key, :value) in setup.entries) {
    if (value == null || value is Map || value is List) {
      continue;
    }
    final known = _knownKeys[key];
    final group = known?.group ?? _other;
    final item = (label: known?.label ?? key, value: formatSetupValue(value, unit: known?.unit ?? _none));
    byGroup[group] = [...?byGroup[group], item];
  }
  return [
    for (final title in _groupOrder)
      if (byGroup[title] case final items? when items.isNotEmpty) (title: title, items: _ordered(title, items)),
  ];
}

/// 알려진 키는 표 순서대로, 모르는 키는 그 뒤에 들어온 순서대로.
List<SetupItem> _ordered(String group, List<SetupItem> items) {
  final order = [
    for (final MapEntry(:value) in _knownKeys.entries)
      if (value.group == group) value.label,
  ];
  int rank(SetupItem item) {
    final index = order.indexOf(item.label);
    return index < 0 ? order.length : index;
  }

  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final byRank = rank(a.$2).compareTo(rank(b.$2));
    return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
  });
  return [for (final (_, item) in indexed) item];
}
