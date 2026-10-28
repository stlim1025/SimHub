import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../domain/car_setup.dart';

const EdgeInsets _cardPadding = EdgeInsets.all(16);
const double _sectionGap = 16;
const double _rowGap = 12;
const double _iconSize = 18;
const double _iconGap = 10;
const double _lineGap = 2;

const String _title = '셋업 진단';
const String _trackTitle = '트랙 적합성';
const String _itemsTitle = '항목별 효과';

/// 셋업 진단 카드: 전체 밸런스(오버·언더스티어 경향), 이 트랙에 맞는지, 항목마다 이 값이 차에 주는 효과.
class SetupDiagnosisCard extends StatelessWidget {
  const SetupDiagnosisCard({super.key, required this.setup, required this.trackName});

  final CarSetup setup;
  final String trackName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diagnosis = diagnoseSetup(setup, trackName);
    final heading = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return Card(
      key: const ValueKey('setup-diagnosis'),
      child: Padding(
        padding: _cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: _rowGap),
            Text(diagnosis.balance, key: const ValueKey('setup-balance'), style: const TextStyle(fontWeight: FontWeight.w600)),
            if (diagnosis.trackFit.isNotEmpty) ...[
              const SizedBox(height: _sectionGap),
              Text(_trackTitle, style: heading),
              const SizedBox(height: _rowGap),
              for (final f in diagnosis.trackFit) _FindingRow(finding: f),
            ],
            const SizedBox(height: _sectionGap),
            Text(_itemsTitle, style: heading),
            const SizedBox(height: _rowGap),
            for (final f in diagnosis.findings) _FindingRow(finding: f),
          ],
        ),
      ),
    );
  }
}

/// 진단 한 줄: 성격 아이콘 · `영역 — 설정`, 아래 효과 설명.
class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final SetupFinding finding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icon, color) = switch (finding.tone) {
      SetupTone.good => (Icons.check_circle_outline, palette.success),
      SetupTone.caution => (Icons.warning_amber_rounded, palette.podiumGold),
      SetupTone.info => (Icons.info_outline, palette.textMuted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: _iconSize, color: color),
          const SizedBox(width: _iconGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${finding.area} — ${finding.setting}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: _lineGap),
                Text(finding.effect, style: TextStyle(color: palette.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
