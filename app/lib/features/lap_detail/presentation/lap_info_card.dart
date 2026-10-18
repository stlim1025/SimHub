import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/track_flag.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/presentation/lap_cells.dart';
import '../../sessions/domain/session_display.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';
import 'detail_list.dart';

const double _inlineGap = 6;
const double _statusIconSize = 16;
const double _copyIconSize = 16;
const String _copyTooltip = '랩 ID 복사';
const String _copiedText = '랩 ID를 복사했어요';
const String _copyFailedText = '복사하지 못했어요. 직접 선택해 복사해 주세요.';
const String _sessionLinkLabel = '세션 보기';

final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

/// Game Mode 줄 `Driver Career · Race`(docs/15 §10, D-51): 아는 게임 모드 + 세션 유형. 둘 다 모르면 `-`(순수 함수).
String gameModeAndSessionText(String? gameMode, String sessionType) {
  final parts = [
    knownGameModeLabel(gameMode),
    sessionTypeLabel(sessionType),
  ].whereType<String>().where((part) => part != kLapNoValueText);
  return parts.isEmpty ? kDetailNoValueText : parts.join(' · ');
}

/// Lap Details 목록(docs/15 §2.3, §10): Track(국기) · Team · Game Mode(모드 · 세션) · Lap · Lap Valid · Lap ID(복사) · Date · 세션 보기 링크.
class LapInfoCard extends StatelessWidget {
  const LapInfoCard({super.key, required this.detail});

  final LapDetail detail;

  @override
  Widget build(BuildContext context) {
    final lap = detail.lap;
    final sessionId = detail.sessionId;
    return SectionCard(
      title: 'Lap Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailList(items: [
            DetailItem('Track', value: _TrackValue(name: lap.trackName, countryCode: detail.countryCode)),
            DetailItem('Team', value: LapTeamCell(lap: lap)),
            DetailItem('Game Mode', text: gameModeAndSessionText(lap.gameMode, lap.sessionType)),
            DetailItem('Lap', text: lap.lapNumber?.toString() ?? kDetailNoValueText),
            DetailItem('Lap Valid', value: _ValidValue(isValid: lap.isValid)),
            DetailItem('Lap ID', value: _LapIdValue(lapId: lap.lapId)),
            DetailItem('Date', text: _dateTimeFormat.format(lap.setAt.toLocal())),
          ]),
          if (sessionId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go(sessionLocation(sessionId)),
                icon: const Icon(Icons.flag_outlined),
                label: const Text(_sessionLinkLabel),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackValue extends StatelessWidget {
  const _TrackValue({required this.name, required this.countryCode});

  final String name;
  final String? countryCode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TrackFlag(countryCode: countryCode),
        const SizedBox(width: _inlineGap),
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _ValidValue extends StatelessWidget {
  const _ValidValue({required this.isValid});

  final bool isValid;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = isValid ? palette.success : palette.danger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isValid ? Icons.check_circle : Icons.cancel, size: _statusIconSize, color: color),
        const SizedBox(width: _inlineGap),
        Text(isValid ? 'Valid' : 'Invalid', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Lap ID 앞 8자 + 복사 버튼(전체 Id를 클립보드에).
class _LapIdValue extends StatelessWidget {
  const _LapIdValue({required this.lapId});

  final String lapId;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: lapId));
      messenger.showSnackBar(const SnackBar(content: Text(_copiedText)));
    } on PlatformException {
      messenger.showSnackBar(const SnackBar(content: Text(_copyFailedText)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(shortLapId(lapId), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        IconButton(
          tooltip: _copyTooltip,
          visualDensity: VisualDensity.compact,
          iconSize: _copyIconSize,
          onPressed: () => _copy(context),
          icon: const Icon(Icons.copy),
        ),
      ],
    );
  }
}
