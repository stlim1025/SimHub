import 'package:flutter/painting.dart';

/// `#RRGGBB`만 받는다(대소문자 무시). `#RGB`·알파 포함·이름 색 등은 모두 거른다.
final RegExp _hexColorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

const int _opaqueAlpha = 0xFF000000;

/// API가 준 `#RRGGBB` 문자열을 불투명 [Color]로 바꾼다. null이거나 형식이 틀리면 [fallback](순수 함수).
Color parseHexColor(String? hex, {required Color fallback}) {
  if (hex == null || !_hexColorPattern.hasMatch(hex)) {
    return fallback;
  }
  return Color(_opaqueAlpha | int.parse(hex.substring(1), radix: 16));
}
