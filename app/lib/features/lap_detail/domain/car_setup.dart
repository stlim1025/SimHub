/// 랩 끝 차량 셋업(스냅샷 `details.setup`, F1 25 값 그대로)과 셋업 진단(순수 계산).
library;

/// F1 25 셋업 값 범위(게임 화면 기준).
const double _wingMax = 50;
const double _diffMin = 10;
const double _diffMax = 100;
const double _suspensionMin = 1;
const double _suspensionMax = 41;
const double _antiRollMin = 1;
const double _antiRollMax = 21;
const double _frontCamberMin = -3.5;
const double _frontCamberMax = -2.5;
const double _rearCamberMin = -2.0;
const double _rearCamberMax = -1.0;
const double _frontPressureMin = 22.5;
const double _frontPressureMax = 29.5;
const double _rearPressureMin = 20.5;
const double _rearPressureMax = 26.5;

/// 판단 기준(범위 안 위치 0~1): 높음·낮음.
const double _high = 0.75;
const double _low = 0.25;

/// 공기압은 범위 끝에 더 가까울 때만 짚는다.
const double _pressureMargin = 0.05;

/// 앞뒤 윙 차이(클릭)·안티롤바 차이(범위 비율)를 밸런스 차이로 볼 기준.
const double _wingSplit = 8;
const double _antiRollSplit = 0.3;

/// 디퍼렌셜: 열림(온스로틀)·열림/잠김(오프스로틀) 기준(범위 비율).
const double _onThrottleOpen = 0.4;
const double _offThrottleOpen = 0.3;
const double _offThrottleLocked = 0.7;

/// 엔진 브레이크(%): 강함·약함.
const double _engineBrakingHigh = 70;
const double _engineBrakingLow = 30;

/// 레이크(리어 − 프론트 라이드 높이): 큼·작음.
const double _rakeHigh = 20;
const double _rakeLow = 5;

/// 브레이크 압력(%)·앞 밸런스(%).
const double _brakePressureHigh = 95;
const double _brakePressureLow = 85;
const double _brakeBiasFront = 58;
const double _brakeBiasRear = 52;

/// 토: 프론트 많음, 리어 많음·적음(°).
const double _frontToeHigh = 0.25;
const double _rearToeHigh = 0.3;
const double _rearToeLow = 0.12;

/// 다운포스 수준을 나누는 윙 평균(0~50): 이 아래 = 낮음, 이 위 = 높음.
const double _lowDownforceWing = 18;
const double _highDownforceWing = 36;

/// 밸런스 점수(+ = 오버스티어 쪽)에 더하는 무게, 경향으로 볼 기준.
const double _wingWeight = 2;
const double _diffWeight = 0.5;
const double _rearSpringWeight = 0.3;
const double _smallLean = 0.15;
const double _engineBrakeLean = 0.2;
const double _balanceLean = 0.3;
const double _middle = 0.5;

double? _num(Map<String, dynamic> map, String key) => switch (map[key]) {
      final num v => v.toDouble(),
      _ => null,
    };

/// 범위 안 위치(0 = [min], 1 = [max]).
double _norm(double v, double min, double max) => ((v - min) / (max - min)).clamp(0.0, 1.0);

String _f(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// 차량 셋업. 값이 없으면 그 진단을 건너뛴다.
class CarSetup {
  const CarSetup({
    this.frontWing,
    this.rearWing,
    this.onThrottle,
    this.offThrottle,
    this.engineBraking,
    this.frontCamber,
    this.rearCamber,
    this.frontToe,
    this.rearToe,
    this.frontSuspension,
    this.rearSuspension,
    this.frontAntiRollBar,
    this.rearAntiRollBar,
    this.frontRideHeight,
    this.rearRideHeight,
    this.brakePressure,
    this.brakeBias,
    this.frontTyrePressure,
    this.rearTyrePressure,
  });

  final double? frontWing;
  final double? rearWing;
  final double? onThrottle;
  final double? offThrottle;
  final double? engineBraking;
  final double? frontCamber;
  final double? rearCamber;
  final double? frontToe;
  final double? rearToe;
  final double? frontSuspension;
  final double? rearSuspension;
  final double? frontAntiRollBar;
  final double? rearAntiRollBar;
  final double? frontRideHeight;
  final double? rearRideHeight;
  final double? brakePressure;
  final double? brakeBias;

  /// 앞·뒤 타이어 공기압(psi, 좌우 평균).
  final double? frontTyrePressure;
  final double? rearTyrePressure;

  /// 스냅샷 `details.setup` 객체. 윙 값조차 없으면 null.
  static CarSetup? fromJsonOrNull(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    double? average(String a, String b) {
      final x = _num(json, a);
      final y = _num(json, b);
      return x == null || y == null ? x ?? y : (x + y) / 2;
    }

    final setup = CarSetup(
      frontWing: _num(json, 'frontWing'),
      rearWing: _num(json, 'rearWing'),
      onThrottle: _num(json, 'onThrottle'),
      offThrottle: _num(json, 'offThrottle'),
      engineBraking: _num(json, 'engineBraking'),
      frontCamber: _num(json, 'frontCamber'),
      rearCamber: _num(json, 'rearCamber'),
      frontToe: _num(json, 'frontToe'),
      rearToe: _num(json, 'rearToe'),
      frontSuspension: _num(json, 'frontSuspension'),
      rearSuspension: _num(json, 'rearSuspension'),
      frontAntiRollBar: _num(json, 'frontAntiRollBar'),
      rearAntiRollBar: _num(json, 'rearAntiRollBar'),
      frontRideHeight: _num(json, 'frontSuspensionHeight'),
      rearRideHeight: _num(json, 'rearSuspensionHeight'),
      brakePressure: _num(json, 'brakePressure'),
      brakeBias: _num(json, 'brakeBias'),
      frontTyrePressure: average('tyrePressureFL', 'tyrePressureFR'),
      rearTyrePressure: average('tyrePressureRL', 'tyrePressureRR'),
    );
    return setup.frontWing == null && setup.rearWing == null ? null : setup;
  }
}

/// 진단 한 줄의 성격: 장점(맞는 선택)·주의(위험·약점)·정보(성향).
enum SetupTone { good, caution, info }

/// 진단 한 줄: 영역(`공력`), 설정과 값(`프론트 40 · 리어 26`), 효과 설명.
typedef SetupFinding = ({String area, String setting, String effect, SetupTone tone});

/// 트랙이 원하는 다운포스 수준.
enum DownforceDemand { low, medium, high }

/// 트랙 이름(서버 트랙 이름) → 다운포스 수요. 없으면 중간.
const Map<String, DownforceDemand> kTrackDownforce = {
  'Monza': DownforceDemand.low,
  'Las Vegas': DownforceDemand.low,
  'Baku (Azerbaijan)': DownforceDemand.low,
  'Jeddah': DownforceDemand.low,
  'Spa': DownforceDemand.low,
  'Monaco': DownforceDemand.high,
  'Singapore': DownforceDemand.high,
  'Hungaroring': DownforceDemand.high,
  'Zandvoort': DownforceDemand.high,
  'Zandvoort (Reverse)': DownforceDemand.high,
  'Mexico': DownforceDemand.high,
};

/// 연석·노면 요철이 많아 부드러운 서스펜션이 유리한 트랙.
const Set<String> kBumpyTracks = {
  'Monaco',
  'Singapore',
  'Baku (Azerbaijan)',
  'Jeddah',
  'Las Vegas',
  'Montreal',
  'Madrid (Madring)',
  'Miami',
};

const Map<DownforceDemand, String> _demandText = {
  DownforceDemand.low: '저다운포스(긴 직선)',
  DownforceDemand.medium: '중간 다운포스',
  DownforceDemand.high: '고다운포스(저속·중속 코너 많음)',
};

/// 셋업 진단 결과: 전체 밸런스 한 줄, 트랙 적합성 줄들, 항목별 진단.
typedef SetupDiagnosis = ({String balance, List<SetupFinding> trackFit, List<SetupFinding> findings});

/// [setup]이 차 거동에 주는 효과를 항목별로 풀고, 전체 밸런스(오버·언더스티어 경향)와 [trackName]에 맞는지 판단한다.
SetupDiagnosis diagnoseSetup(CarSetup setup, String trackName) {
  final findings = <SetupFinding>[];
  var oversteer = 0.0;
  void add(String area, String setting, String effect, SetupTone tone) =>
      findings.add((area: area, setting: setting, effect: effect, tone: tone));

  // 공력.
  final fw = setup.frontWing;
  final rw = setup.rearWing;
  double? wingAverage;
  if (fw != null && rw != null) {
    final average = (fw + rw) / 2;
    wingAverage = average;
    final setting = '프론트 ${_f(fw)} · 리어 ${_f(rw)}';
    if (average < _lowDownforceWing) {
      add('공력', setting, '다운포스가 낮아요 → 직선 최고속도가 빠르지만 코너 그립이 적어 고속 코너에서 차가 미끄러지기 쉬워요.', SetupTone.info);
    } else if (average > _highDownforceWing) {
      add('공력', setting, '다운포스가 높아요 → 코너 그립과 안정감이 크지만 공기저항 때문에 직선 최고속도가 느려요.', SetupTone.info);
    } else {
      add('공력', setting, '중간 다운포스예요 → 직선 속도와 코너 그립의 균형형이에요.', SetupTone.info);
    }
    final split = fw - rw;
    oversteer += split / _wingMax * _wingWeight;
    if (split >= _wingSplit) {
      add('공력 밸런스', '프론트가 ${_f(split)} 높음',
          '앞이 잘 들어가 턴인은 날카롭지만 리어 다운포스가 상대적으로 부족해 고속 코너·탈출에서 오버스티어가 나기 쉬워요.', SetupTone.caution);
    } else if (-split >= _wingSplit) {
      add('공력 밸런스', '리어가 ${_f(-split)} 높음', '리어가 안정적이지만 코너 진입·중반에 앞이 밀리는 언더스티어가 나기 쉬워요.', SetupTone.caution);
    } else {
      add('공력 밸런스', '앞뒤 차이 ${_f(split.abs())}', '앞뒤 다운포스가 비슷해 고속에서 중립적인 밸런스예요.', SetupTone.good);
    }
  }

  // 디퍼렌셜·엔진 브레이크.
  final on = setup.onThrottle;
  if (on != null) {
    final n = _norm(on, _diffMin, _diffMax);
    oversteer += (n - _middle) * _diffWeight;
    if (n >= _high) {
      add('디퍼렌셜', '온스로틀 ${_f(on)}%',
          '많이 잠겨 탈출 트랙션은 좋지만 두 뒷바퀴가 함께 돌아 탈출 중 차가 덜 돌고, 스로틀을 거칠게 열면 한꺼번에 휠스핀·파워 오버스티어가 나요. 저속 코너 탈출에서 특히 조심하세요.',
          SetupTone.caution);
    } else if (n <= _onThrottleOpen) {
      add('디퍼렌셜', '온스로틀 ${_f(on)}%', '많이 열려 탈출 때 차가 잘 돌지만 안쪽 바퀴가 헛돌아 트랙션이 떨어져요.', SetupTone.caution);
    } else {
      add('디퍼렌셜', '온스로틀 ${_f(on)}%', '탈출 트랙션과 회전성의 중간이에요.', SetupTone.good);
    }
  }
  final off = setup.offThrottle;
  if (off != null) {
    final n = _norm(off, _diffMin, _diffMax);
    oversteer += (_middle - n) * _diffWeight;
    if (n <= _offThrottleOpen) {
      add('디퍼렌셜', '오프스로틀 ${_f(off)}%', '열려 있어 코너 진입 때 차가 잘 돌아가지만, 브레이킹·진입에서 리어가 흔들리기 쉬워요.', SetupTone.caution);
    } else if (n >= _offThrottleLocked) {
      add('디퍼렌셜', '오프스로틀 ${_f(off)}%', '잠겨 있어 진입이 안정적이지만 진입·코너 중반에 언더스티어가 나기 쉬워요.', SetupTone.caution);
    } else {
      add('디퍼렌셜', '오프스로틀 ${_f(off)}%', '진입 안정성과 회전성의 중간이에요.', SetupTone.good);
    }
  }
  final eb = setup.engineBraking;
  if (eb != null) {
    if (eb >= _engineBrakingHigh) {
      oversteer += _engineBrakeLean;
      add('엔진 브레이크', '${_f(eb)}%', '감속을 많이 도와주지만 뒷바퀴가 잡혀 진입 오버스티어·리어 락업 위험이 커요.', SetupTone.caution);
    } else if (eb <= _engineBrakingLow) {
      add('엔진 브레이크', '${_f(eb)}%', '진입이 안정적이지만 감속을 브레이크에 더 의존해요.', SetupTone.info);
    } else {
      add('엔진 브레이크', '${_f(eb)}%', '감속 보조와 진입 안정의 중간이에요.', SetupTone.good);
    }
  }

  // 서스펜션·안티롤바.
  final fs = setup.frontSuspension;
  final rs = setup.rearSuspension;
  if (fs != null) {
    final n = _norm(fs, _suspensionMin, _suspensionMax);
    if (n >= _high) {
      add('서스펜션', '프론트 ${_f(fs)} (단단함)', '턴인 반응과 공력 플랫폼은 좋지만 연석·요철에서 튀고 앞 그립이 떨어질 수 있어요.', SetupTone.info);
    } else if (n <= _low) {
      add('서스펜션', '프론트 ${_f(fs)} (부드러움)', '연석·요철을 잘 흡수하고 앞 기계적 그립이 좋지만 반응이 둔하고 브레이킹 때 앞이 많이 숙여요.', SetupTone.info);
    }
  }
  if (rs != null) {
    final n = _norm(rs, _suspensionMin, _suspensionMax);
    oversteer += (n - _middle) * _rearSpringWeight;
    if (n >= _high) {
      add('서스펜션', '리어 ${_f(rs)} (단단함)', '반응은 빠르지만 탈출 트랙션이 줄고 리어가 먼저 미끄러지는 오버스티어 경향이 생겨요.', SetupTone.caution);
    } else if (n <= _low) {
      add('서스펜션', '리어 ${_f(rs)} (부드러움)', '탈출 트랙션은 좋지만 빠른 방향 전환에서 리어가 출렁여 반응이 늦어요.', SetupTone.info);
    }
  }
  final fa = setup.frontAntiRollBar;
  final ra = setup.rearAntiRollBar;
  if (fa != null && ra != null) {
    final diff = _norm(ra, _antiRollMin, _antiRollMax) - _norm(fa, _antiRollMin, _antiRollMax);
    oversteer += diff;
    final setting = '프론트 ${_f(fa)} · 리어 ${_f(ra)}';
    if (diff >= _antiRollSplit) {
      add('안티롤바', setting, '리어가 더 단단해 코너 중반 회전성은 좋지만 리어가 먼저 미끄러져 오버스티어가 나기 쉬워요.', SetupTone.caution);
    } else if (-diff >= _antiRollSplit) {
      add('안티롤바', setting, '프론트가 더 단단해 안정적이지만 코너 중반에 앞이 밀리는 언더스티어가 나기 쉬워요.', SetupTone.caution);
    } else {
      add('안티롤바', setting, '앞뒤 강성이 비슷해 코너 중반 밸런스가 중립적이에요.', SetupTone.good);
    }
  }

  // 라이드 높이(레이크).
  final fh = setup.frontRideHeight;
  final rh = setup.rearRideHeight;
  if (fh != null && rh != null) {
    final rake = rh - fh;
    final setting = '프론트 ${_f(fh)} · 리어 ${_f(rh)}';
    if (rake >= _rakeHigh) {
      oversteer += _smallLean;
      add('라이드 높이', setting, '레이크(뒤가 높음)가 커서 저속 코너 회전성과 앞 다운포스는 좋지만 고속에서 리어가 가벼워 불안정해요.', SetupTone.caution);
    } else if (rake <= _rakeLow) {
      add('라이드 높이', setting, '레이크가 작아 고속 안정성은 좋지만 저속 코너에서 차가 잘 안 돌아요.', SetupTone.info);
    } else {
      add('라이드 높이', setting, '레이크가 적당해 저속 회전성과 고속 안정의 균형형이에요.', SetupTone.good);
    }
  }

  // 브레이크.
  final bp = setup.brakePressure;
  if (bp != null) {
    if (bp >= _brakePressureHigh) {
      add('브레이크', '압력 ${_f(bp)}%', '제동력이 최대라 짧게 설 수 있지만 ABS 없이 끝까지 밟으면 락업이 쉽게 걸려요(연석 위·젖은 노면에서 특히).', SetupTone.caution);
    } else if (bp <= _brakePressureLow) {
      add('브레이크', '압력 ${_f(bp)}%', '락업은 덜하지만 제동 거리가 길어져요.', SetupTone.info);
    } else {
      add('브레이크', '압력 ${_f(bp)}%', '제동력과 락업 위험의 균형이에요.', SetupTone.good);
    }
  }
  final bb = setup.brakeBias;
  if (bb != null) {
    if (bb >= _brakeBiasFront) {
      oversteer -= _smallLean;
      add('브레이크', '밸런스 앞 ${_f(bb)}%', '브레이킹이 안정적이지만 앞바퀴 락업과 진입 언더스티어가 나기 쉬워요.', SetupTone.caution);
    } else if (bb <= _brakeBiasRear) {
      oversteer += _smallLean;
      add('브레이크', '밸런스 앞 ${_f(bb)}%', '진입 회전성은 좋지만 뒷바퀴 락업·브레이킹 중 스핀 위험이 커요.', SetupTone.caution);
    } else {
      add('브레이크', '밸런스 앞 ${_f(bb)}%', '앞뒤 제동 배분이 무난해요.', SetupTone.good);
    }
  }

  // 캠버·토.
  final fc = setup.frontCamber;
  if (fc != null && _norm(fc, _frontCamberMax, _frontCamberMin) >= _high) {
    add('캠버', '프론트 ${_f(fc)}°', '코너 그립과 턴인은 좋아지지만 직선 브레이킹 접지면이 줄어 락업이 쉽고 타이어 안쪽이 과열·마모돼요.', SetupTone.caution);
  }
  final rc = setup.rearCamber;
  if (rc != null && _norm(rc, _rearCamberMax, _rearCamberMin) >= _high) {
    add('캠버', '리어 ${_f(rc)}°', '코너 중 리어 그립은 좋지만 탈출 직선 트랙션이 줄고 뒷타이어 안쪽이 빨리 닳아요.', SetupTone.caution);
  }
  final ft = setup.frontToe;
  if (ft != null && ft >= _frontToeHigh) {
    add('토', '프론트 ${_f(ft)}°', '턴인 반응은 빨라지지만 직선 안정성이 떨어지고 타이어 온도·저항이 늘어요.', SetupTone.info);
  }
  final rt = setup.rearToe;
  if (rt != null) {
    if (rt >= _rearToeHigh) {
      oversteer -= _smallLean;
      add('토', '리어 ${_f(rt)}°', '리어 안정성이 커져 오버스티어를 누르지만 직선 속도와 타이어 수명을 잃어요.', SetupTone.info);
    } else if (rt <= _rearToeLow) {
      oversteer += _smallLean;
      add('토', '리어 ${_f(rt)}°', '직선에 유리하지만 리어 안정성이 낮아 코너·탈출에서 오버스티어가 나기 쉬워요.', SetupTone.caution);
    }
  }

  // 타이어 공기압.
  final fp = setup.frontTyrePressure;
  if (fp != null) {
    final n = _norm(fp, _frontPressureMin, _frontPressureMax);
    if (n >= _high + _pressureMargin) {
      add('타이어 공기압', '앞 ${fp.toStringAsFixed(1)}psi (높음)', '반응이 빠르고 구름저항이 줄지만 접지면이 작아 앞 그립이 떨어지고 과열·마모가 빨라요.', SetupTone.caution);
    } else if (n <= _low - _pressureMargin) {
      add('타이어 공기압', '앞 ${fp.toStringAsFixed(1)}psi (낮음)', '앞 그립은 좋지만 반응이 둔하고 직선 저항이 늘어요.', SetupTone.info);
    }
  }
  final rp = setup.rearTyrePressure;
  if (rp != null) {
    final n = _norm(rp, _rearPressureMin, _rearPressureMax);
    if (n >= _high + _pressureMargin) {
      add('타이어 공기압', '뒤 ${rp.toStringAsFixed(1)}psi (높음)', '직선 속도엔 유리하지만 탈출 트랙션이 줄고 휠스핀·과열이 쉬워요.', SetupTone.caution);
    } else if (n <= _low - _pressureMargin) {
      add('타이어 공기압', '뒤 ${rp.toStringAsFixed(1)}psi (낮음)', '탈출 트랙션은 좋지만 반응이 둔하고 마모가 늘 수 있어요.', SetupTone.info);
    }
  }

  final balance = oversteer >= _balanceLean
      ? '전체적으로 오버스티어 경향이에요 — 리어가 먼저 미끄러지기 쉬우니 탈출에서 스로틀을 부드럽게 여세요.'
      : oversteer <= -_balanceLean
          ? '전체적으로 언더스티어 경향이에요 — 코너에서 앞이 밀리기 쉬우니 진입 속도를 조금 낮추세요.'
          : '전체 밸런스는 중립에 가까워요.';

  // 트랙 적합성.
  final trackFit = <SetupFinding>[];
  final demand = kTrackDownforce[trackName] ?? DownforceDemand.medium;
  final average = wingAverage;
  if (average != null) {
    final setting = '$trackName · ${_demandText[demand]}';
    final level = average < _lowDownforceWing
        ? DownforceDemand.low
        : average > _highDownforceWing
            ? DownforceDemand.high
            : DownforceDemand.medium;
    final (effect, tone) = level == demand
        ? ('윙 수준이 이 트랙에 맞아요.', SetupTone.good)
        : level.index > demand.index
            ? ('이 트랙에 비해 윙이 높아요 → 직선에서 최고속도를 잃어요. 윙을 낮춰 보세요.', SetupTone.caution)
            : ('이 트랙에 비해 윙이 낮아요 → 코너 그립이 부족해 랩타임을 잃어요. 윙을 올려 보세요.', SetupTone.caution);
    trackFit.add((area: '다운포스', setting: setting, effect: effect, tone: tone));
  }
  if (kBumpyTracks.contains(trackName) && fs != null && rs != null) {
    final stiffness = (_norm(fs, _suspensionMin, _suspensionMax) + _norm(rs, _suspensionMin, _suspensionMax)) / 2;
    final (effect, tone) = stiffness >= _middle
        ? ('연석과 요철이 많은 트랙인데 서스펜션이 단단한 편이에요 → 연석에서 튀고 불안정해요. 부드럽게 해 보세요.', SetupTone.caution)
        : ('연석과 요철이 많은 트랙에 맞게 서스펜션이 부드러운 편이에요.', SetupTone.good);
    trackFit.add((area: '서스펜션', setting: '$trackName · 연석·요철 많음', effect: effect, tone: tone));
  }
  return (balance: balance, trackFit: trackFit, findings: findings);
}
