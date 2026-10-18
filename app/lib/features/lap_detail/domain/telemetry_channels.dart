import 'package:intl/intl.dart';

import '../../auth/domain/user_preferences.dart';
import 'lap_detail_models.dart';
import 'telemetry_math.dart';

/// 퍼센트 채널(스로틀·브레이크) 범위.
const double _percentMin = 0;
const double _percentMax = 100;

/// 스티어 범위(−100 왼쪽 끝 ~ 100 오른쪽 끝).
const double _steerMin = -100;
const double _steerMax = 100;

/// 기어 범위(−1 = R, 0 = N, 1~8).
const double _gearMin = -1;
const double _gearMax = 8;
const int _reverseGear = -1;
const int _neutralGear = 0;

final NumberFormat _integerFormat = NumberFormat('#,##0');

/// 텔레메트리 그래프 한 장의 채널(docs/15 §2.3, 위에서 아래 순서). Delta는 따로 그린다.
enum TelemetryChannel { speed, throttle, brake, gear, steer, rpm }

/// 화면에 쌓는 순서.
const List<TelemetryChannel> kTelemetryChannels = TelemetryChannel.values;

extension TelemetryChannelInfo on TelemetryChannel {
  /// 그래프 제목.
  String get title => switch (this) {
        TelemetryChannel.speed => 'Speed',
        TelemetryChannel.throttle => 'Throttle',
        TelemetryChannel.brake => 'Brake',
        TelemetryChannel.gear => 'Gear',
        TelemetryChannel.steer => 'Steering',
        TelemetryChannel.rpm => 'RPM',
      };

  /// 트레이스의 이 채널 값. 속도는 [units]에 맞춘다(Imperial이면 mph).
  List<double> valuesOf(LapTrace trace, UnitSystem units) => switch (this) {
        TelemetryChannel.speed => [
            for (final kph in trace.speedKph) units == UnitSystem.imperial ? kphToMph(kph) : kph.toDouble(),
          ],
        TelemetryChannel.throttle => _doubles(trace.throttle),
        TelemetryChannel.brake => _doubles(trace.brake),
        TelemetryChannel.gear => _doubles(trace.gear),
        TelemetryChannel.steer => _doubles(trace.steer),
        TelemetryChannel.rpm => _doubles(trace.rpm),
      };

  /// 세로축 범위. 고정 범위가 없는 채널(속도·RPM)은 0부터 값의 최댓값까지.
  ValueRange rangeOf(Iterable<double?> values) => switch (this) {
        TelemetryChannel.throttle || TelemetryChannel.brake =>
          valueRangeOf(values, fixedMin: _percentMin, fixedMax: _percentMax),
        TelemetryChannel.steer => valueRangeOf(values, fixedMin: _steerMin, fixedMax: _steerMax),
        TelemetryChannel.gear => valueRangeOf(values, fixedMin: _gearMin, fixedMax: _gearMax),
        TelemetryChannel.speed || TelemetryChannel.rpm => valueRangeOf(values, fixedMin: 0),
      };

  /// 십자선 값 글자: `287 km/h`·`178 mph`·`85%`·`N`·`-34`·`11,500`.
  String format(double value, UnitSystem units) => switch (this) {
        TelemetryChannel.speed => '${value.round()} ${units == UnitSystem.imperial ? 'mph' : 'km/h'}',
        TelemetryChannel.throttle || TelemetryChannel.brake => '${value.round()}%',
        TelemetryChannel.gear => gearLabel(value.round()),
        TelemetryChannel.steer => '${value.round()}',
        TelemetryChannel.rpm => _integerFormat.format(value.round()),
      };
}

/// 기어 글자: −1 → `R`, 0 → `N`, 그 밖은 숫자(순수 함수).
String gearLabel(int gear) => switch (gear) {
      _reverseGear => 'R',
      _neutralGear => 'N',
      _ => '$gear',
    };

/// Delta(초) 글자: `+0.123s`·`-0.045s`·`0.000s`(순수 함수).
String formatDeltaSeconds(double seconds) {
  final text = seconds.abs().toStringAsFixed(3);
  if (text == '0.000') {
    return '0.000s';
  }
  return '${seconds < 0 ? '-' : '+'}${text}s';
}

/// 거리 글자 `1,235 m`(순수 함수).
String formatDistance(double meters) => '${_integerFormat.format(meters.round())} m';

List<double> _doubles(List<int> values) => [for (final v in values) v.toDouble()];
