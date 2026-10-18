import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 국기 기본 지름(트랙 메뉴 줄·표 안).
const double kTrackFlagSize = 20;

/// ISO 3166-1 alpha-2(두 글자)만 국기로 그린다.
final RegExp _alpha2Pattern = RegExp(r'^[A-Za-z]{2}$');

/// 트랙 국기(D-43, docs/15 §2.2): `country_flags`의 원형 SVG 국기. 코드가 없거나 모르는 코드면 회색 원.
/// 국기 이모지는 Windows 브라우저가 그리지 못해 쓰지 않는다. 장식이라 읽기 도구에는 숨긴다(옆에 트랙 이름이 있다).
class TrackFlag extends StatelessWidget {
  const TrackFlag({super.key, required this.countryCode, this.size = kTrackFlagSize});

  final String? countryCode;
  final double size;

  /// 그릴 수 있는 국기 코드(대문자). 없거나 모르는 코드면 null(순수 함수).
  static String? flagCodeOf(String? countryCode) {
    if (countryCode == null || !_alpha2Pattern.hasMatch(countryCode)) {
      return null;
    }
    final upper = countryCode.toUpperCase();
    return FlagCode.fromCountryCode(upper) == null ? null : upper;
  }

  @override
  Widget build(BuildContext context) {
    final code = flagCodeOf(countryCode);
    final Widget flag = code == null
        ? Container(
            key: const ValueKey('track-flag-fallback'),
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: context.palette.border),
          )
        : SizedBox(
            key: ValueKey('track-flag-$code'),
            width: size,
            height: size,
            child: CountryFlag.fromCountryCode(
              code,
              theme: ImageTheme(width: size, height: size, shape: const Circle()),
            ),
          );
    return ExcludeSemantics(child: flag);
  }
}
