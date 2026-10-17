import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/util/hex_color.dart';

const _fallback = Color(0xFF123456);

void main() {
  group('parseHexColor', () {
    test('#RRGGBB는 불투명 색으로 바뀐다', () {
      expect(parseHexColor('#FF8000', fallback: _fallback), const Color(0xFFFF8000));
    });

    test('소문자 16진수도 받는다', () {
      expect(parseHexColor('#3671c6', fallback: _fallback), const Color(0xFF3671C6));
    });

    test('null·이름·#RGB·#RRGGBBAA·# 없음·잘못된 문자는 대체 색이다', () {
      for (final bad in [null, '', 'red', '#FFF', '#FF8000AA', 'FF8000', '#GG8000', ' #FF8000', '#FF8000\n']) {
        expect(parseHexColor(bad, fallback: _fallback), _fallback, reason: '$bad');
      }
    });
  });
}
