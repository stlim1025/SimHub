import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/track_flag.dart';

const String _crumbSeparator = '/';
const double _crumbGap = 6;
const double _crumbTitleGap = 8;
const double _subtitleGap = 4;
const double _introGap = 12;
const double _flagSize = 28;
const double _flagGap = 12;

/// 이동 경로 한 칸. [path]가 있으면 눌러서 그곳으로 간다.
typedef Crumb = ({String label, String? path});

/// F1Laps 모양의 화면 머리: 흐린 이동 경로(`F1 2025 / Setups / Australia`) + 큰 제목(+국기) + 흐린 부제 + 안내 문장.
/// Setups·Tracks 화면이 같이 쓴다.
class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.crumbs,
    required this.title,
    this.subtitle,
    this.intro,
    this.countryCode,
    this.showFlag = false,
  });

  final List<Crumb> crumbs;
  final String title;
  final String? subtitle;
  final String? intro;

  /// [showFlag]일 때 제목 앞 국기.
  final String? countryCode;
  final bool showFlag;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = context.palette.textMuted;
    final mutedStyle = textTheme.bodyMedium?.copyWith(color: muted);
    final subtitleText = subtitle;
    final introText = intro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: _crumbGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < crumbs.length; i++) ...[
              if (i > 0) Text(_crumbSeparator, style: textTheme.bodySmall?.copyWith(color: muted)),
              _CrumbLink(crumb: crumbs[i]),
            ],
          ],
        ),
        const SizedBox(height: _crumbTitleGap),
        Row(
          children: [
            if (showFlag) ...[
              TrackFlag(countryCode: countryCode, size: _flagSize),
              const SizedBox(width: _flagGap),
            ],
            Flexible(
              child: Text(
                title,
                style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (subtitleText != null) ...[
          const SizedBox(height: _subtitleGap),
          Text(subtitleText, style: mutedStyle),
        ],
        if (introText != null) ...[
          const SizedBox(height: _introGap),
          Text(introText, style: mutedStyle),
        ],
      ],
    );
  }
}

class _CrumbLink extends StatelessWidget {
  const _CrumbLink({required this.crumb});

  final Crumb crumb;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted);
    final path = crumb.path;
    final text = Text(crumb.label, style: style);
    if (path == null) {
      return text;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: () => context.go(path), child: text),
    );
  }
}
