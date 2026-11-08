import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/track_flag.dart';
import '../domain/session_board.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';

const String _highlightsLabel = '하이라이트';

/// 띠 안쪽 여백·칸 사이 여백.
const EdgeInsets _stripPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
const double _cellPaddingX = 20;
const double _stackGap = 12;
const double _runGap = 14;

/// 한 줄로 둘지 정하는 폭: 헤더 칸 + KPI 칸 최소 폭 × 개수 + 하이라이트 버튼 자리. 헤더 칸은 많아야 [_identityMaxWidth].
const double _identityMinWidth = 260;
const double _identityMaxWidth = 380;
const double _kpiMinWidth = 124;
const double _buttonReserve = 150;

/// 헤더 칸(뒤로 + 경로 + 국기·트랙·세션 종류) 글자·국기.
const double _crumbFontSize = 13;
const double _titleFontSize = 24;
const double _flagSize = 22;
const double _titleGap = 8;

/// KPI 칸 글자(작은 대문자 이름 · 큰 값 · 보조 줄).
const double _labelFontSize = 12;
const double _labelLetterSpacing = 1.6;
const double _valueFontSize = 30;
const double _valueLineHeight = 1.1;
const double _subFontSize = 14;
const double _lineGap = 2;

/// 세션 상세 맨 위 KPI 띠(B안 미션 컨트롤): 뒤로 + `Sessions ›` + 국기·트랙·세션 종류 | Finish · Gap to P1 · Best Lap ·
/// Pit · Penalty · Points(레이스, 예선·연습은 Position · Best Lap · Gap) | 하이라이트 버튼.
/// 넓으면 한 줄, 좁으면 헤더 줄 아래에 KPI 칸을 여러 줄로 둔다.
class SessionKpiStrip extends StatelessWidget {
  const SessionKpiStrip({
    super.key,
    required this.detail,
    required this.crumb,
    required this.backTooltip,
    required this.onBack,
    this.onHighlights,
  });

  final SessionDetail detail;

  /// 경로 글자(`Sessions`, 시즌에서 열었으면 `Season 1`).
  final String crumb;
  final String backTooltip;
  final VoidCallback onBack;

  /// 레이스 하이라이트 열기(모든 차 표본이 있는 레이스만). null이면 버튼 없음.
  final VoidCallback? onHighlights;

  @override
  Widget build(BuildContext context) {
    final kpis = sessionKpis(detail);
    final identity = _Identity(header: detail.header, crumb: crumb, backTooltip: backTooltip, onBack: onBack);
    final button = onHighlights == null
        ? null
        : FilledButton.icon(
            key: const ValueKey('session-highlights'),
            onPressed: onHighlights,
            icon: const Icon(Icons.play_arrow),
            label: const Text(_highlightsLabel),
          );
    return Card(
      key: const ValueKey('session-kpi-strip'),
      child: Padding(
        padding: _stripPadding,
        child: LayoutBuilder(
          builder: (context, box) {
            final kpiRoom = kpis.length * _kpiMinWidth + (button == null ? 0 : _buttonReserve);
            if (box.maxWidth >= _identityMinWidth + kpiRoom) {
              final identityWidth = math.min(_identityMaxWidth, box.maxWidth - kpiRoom);
              return _inline(context, identity, identityWidth, kpis, button);
            }
            return _stacked(context, box.maxWidth, identity, kpis, button);
          },
        ),
      ),
    );
  }

  /// 한 줄: [헤더 | KPI 칸(같은 비율) … | 버튼], 칸 사이 세로 구분선.
  Widget _inline(BuildContext context, Widget identity, double identityWidth, List<SessionKpi> kpis, Widget? button) {
    final border = BorderSide(color: context.palette.border);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: identityWidth),
            child: Container(
              padding: const EdgeInsets.only(right: _cellPaddingX),
              decoration: BoxDecoration(border: Border(right: border)),
              child: identity,
            ),
          ),
          for (final (i, kpi) in kpis.indexed)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: _cellPaddingX),
                decoration: i == 0 ? null : BoxDecoration(border: Border(left: border)),
                alignment: Alignment.centerLeft,
                child: _KpiCell(kpi: kpi),
              ),
            ),
          if (button != null) Center(child: button),
        ],
      ),
    );
  }

  /// 여러 줄: 헤더 줄(+ 버튼) 아래 구분선, 그 아래 KPI 칸을 같은 폭으로 줄 바꿈.
  Widget _stacked(BuildContext context, double width, Widget identity, List<SessionKpi> kpis, Widget? button) {
    final perRow = kpis.isEmpty ? 1 : (width / _kpiMinWidth).floor().clamp(1, kpis.length);
    final cellWidth = (width / perRow).floorToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 헤더와 버튼이 한 줄에 다 들어가지 않으면(트랙 이름이 잘리지 않게) 버튼을 다음 줄로 보낸다.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: _stackGap,
          children: [identity, ?button],
        ),
        if (kpis.isNotEmpty) ...[
          const SizedBox(height: _stackGap),
          const Divider(height: 1),
          const SizedBox(height: _stackGap),
          Wrap(
            runSpacing: _runGap,
            children: [
              for (final kpi in kpis) SizedBox(width: cellWidth, child: _KpiCell(kpi: kpi)),
            ],
          ),
        ],
      ],
    );
  }
}

/// 헤더 칸: ← + `Sessions ›`(작게) 아래 국기 · 트랙 이름 · 세션 종류.
class _Identity extends StatelessWidget {
  const _Identity({required this.header, required this.crumb, required this.backTooltip, required this.onBack});

  final SessionDetailHeader header;
  final String crumb;
  final String backTooltip;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final title = textTheme.titleLarge?.copyWith(fontSize: _titleFontSize, fontWeight: FontWeight.w700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: backTooltip, icon: const Icon(Icons.arrow_back), onPressed: onBack),
        const SizedBox(width: _lineGap),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$crumb ›',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(fontSize: _crumbFontSize, color: palette.textMuted),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TrackFlag(countryCode: header.countryCode, size: _flagSize),
                  const SizedBox(width: _titleGap),
                  Flexible(
                    child: Text(header.trackName, maxLines: 1, overflow: TextOverflow.ellipsis, style: title),
                  ),
                  Text(' · ', style: title?.copyWith(color: palette.textMuted)),
                  Flexible(
                    child: Text(
                      sessionKindName(header.sessionKind, sprintWeekend: header.isSprintWeekend),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: title?.copyWith(fontWeight: FontWeight.w500, color: palette.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// KPI 한 칸: 이름(작은 대문자, 흐리게) · 값(크고 굵게, [KpiTone] 색) · 보조 줄(없으면 빈 줄로 높이를 맞춘다).
class _KpiCell extends StatelessWidget {
  const _KpiCell({required this.kpi});

  final SessionKpi kpi;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: ValueKey('session-kpi-${kpi.id.name}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kpi.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            fontSize: _labelFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: _labelLetterSpacing,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: _lineGap),
        Text(
          kpi.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.headlineSmall?.merge(kTabularStyle).copyWith(
                fontSize: _valueFontSize,
                height: _valueLineHeight,
                fontWeight: FontWeight.w800,
                color: kpiToneColor(kpi.valueTone, palette),
              ),
        ),
        const SizedBox(height: _lineGap),
        Text(
          kpi.sub ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            fontSize: _subFontSize,
            fontWeight: FontWeight.w600,
            color: kpiToneColor(kpi.subTone, palette),
          ),
        ),
      ],
    );
  }
}

/// [KpiTone] → 글자색(강조는 밝은 테마에서도 읽히는 `link` 앰버, fastest는 세션 최고 랩 보라).
Color kpiToneColor(KpiTone tone, AppPalette palette) => switch (tone) {
      KpiTone.normal => palette.textPrimary,
      KpiTone.accent => palette.link,
      KpiTone.fastest => AppColors.fastestLap,
      KpiTone.success => palette.success,
      KpiTone.danger => palette.danger,
      KpiTone.muted => palette.textMuted,
    };
