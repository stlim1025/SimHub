import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../lap_detail/presentation/track_map.dart';
import '../domain/track_outline.dart';

const double _strokeWidth = 3;

/// 서킷 윤곽 그림(달린 기록이 없는 트랙). 트랙 지도와 같은 높이에 가로세로 비율을 지켜 가운데 그린다(한 색, 섹터 없음).
class TrackOutlineView extends StatelessWidget {
  const TrackOutlineView({super.key, required this.outline});

  final TrackOutline outline;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kTrackMapHeight,
      child: CustomPaint(
        key: const ValueKey('track-outline-map'),
        painter: TrackOutlinePainter(outline),
        size: Size.infinite,
      ),
    );
  }
}

/// 정규화 윤곽을 칸 안에 비율대로 맞춰 닫힌 선으로 그린다.
class TrackOutlinePainter extends CustomPainter {
  const TrackOutlinePainter(this.outline);

  final TrackOutline outline;

  @override
  void paint(Canvas canvas, Size size) {
    if (outline.points.length < 2 || size.isEmpty) {
      return;
    }
    const inset = _strokeWidth;
    final scaleX = (size.width - inset * 2) / outline.width;
    final scaleY = (size.height - inset * 2) / outline.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offset = Offset(
      (size.width - outline.width * scale) / 2,
      (size.height - outline.height * scale) / 2,
    );
    final first = outline.points.first;
    final path = Path()..moveTo(offset.dx + first.dx * scale, offset.dy + first.dy * scale);
    for (final p in outline.points.skip(1)) {
      path.lineTo(offset.dx + p.dx * scale, offset.dy + p.dy * scale);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(TrackOutlinePainter oldDelegate) => oldDelegate.outline != outline;
}
