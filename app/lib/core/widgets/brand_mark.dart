import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

const double _brandMarkSize = 30;

// 웹 아이콘(app/web/favicon.svg)과 같은 512 단위 좌표.
const double _artExtent = 512;
const double _chamferStart = 404;
const double _chamferEnd = 108;
const double _plateBorderWidth = 16;
const double _chevronStroke = 64;
const double _chevronMiterLimit = 4;

/// 웹·Agent 아이콘과 같은 모양의 로고(Cockpit HUD): 오른쪽 위를 깎은 검은 판 + 앰버·흰 ≫ + 비스듬한 앰버 눈금.
/// 사이드바·공유 화면 머리줄이 함께 쓴다.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(size: Size.square(_brandMarkSize), painter: _BrandMarkPainter());
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _artExtent, size.height / _artExtent);
    final plate = Path()
      ..moveTo(0, 0)
      ..lineTo(_chamferStart, 0)
      ..lineTo(_artExtent, _chamferEnd)
      ..lineTo(_artExtent, _artExtent)
      ..lineTo(0, _artExtent)
      ..close();
    Paint chevron(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _chevronStroke
      ..strokeJoin = StrokeJoin.miter
      ..strokeMiterLimit = _chevronMiterLimit;
    canvas
      ..drawPath(plate, Paint()..color = AppColors.background)
      ..drawPath(
        plate,
        Paint()
          ..color = AppColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = _plateBorderWidth,
      )
      ..drawPath(
        Path()
          ..moveTo(126, 150)
          ..lineTo(236, 256)
          ..lineTo(126, 362),
        chevron(AppColors.accent),
      )
      ..drawPath(
        Path()
          ..moveTo(262, 150)
          ..lineTo(372, 256)
          ..lineTo(262, 362),
        chevron(AppColors.textPrimary),
      )
      ..drawPath(
        Path()
          ..moveTo(138, 418)
          ..lineTo(318, 418)
          ..lineTo(302, 444)
          ..lineTo(122, 444)
          ..close(),
        Paint()..color = AppColors.accent,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) => false;
}
