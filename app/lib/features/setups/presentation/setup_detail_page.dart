import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/platform/download_launcher.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/team_name_cell.dart';
import '../../laps/domain/lap_display.dart';
import '../../profile/application/selected_game_provider.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../../sessions/presentation/setup_sections.dart';
import '../application/setups_providers.dart';
import '../domain/setup_models.dart';
import '../domain/setups_display.dart';
import 'page_heading.dart';

const String _setupsLabel = 'Setups';
const String _setupLabel = 'Setup';
const String _viewOnSourceLabel = 'View on F1Laps';
const String _errorMessage = '셋업을 불러오지 못했다.';
const String _notFoundMessage = '찾을 수 없는 셋업이다.';
const String _emptyMessage = '이 셋업에는 보여 줄 값이 없다.';

const String _metaTeam = 'Team';
const String _metaSession = 'Session';
const String _metaLapTime = 'Lap time';
const String _metaConditions = 'Conditions';
const String _metaSteering = 'Steering';
const String _metaDate = 'Date';

const int _httpNotFound = 404;
const double _headingGap = 20;
const double _cardGap = 20;

final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

/// 셋업 상세 제목: `F1 25 Australia Setup (Dry)`(순수 함수).
String setupDetailTitle(SetupDetail detail) =>
    '${gameTitleOf(detail.gameCode)} ${detail.track.name} $_setupLabel (${detail.condition})';

/// 셋업 하나(`/setups/:trackId/:setupId`, F1Laps 셋업 상세 모양): 이동 경로 + 제목(작성자 닉네임은 개인정보라 싣지 않는다),
/// Team · Session · Lap time · Conditions · Steering · Date 요약 카드, 원본 링크, 묶음(Aerodynamics …)별 카드 격자.
/// 카드 모양은 세션 셋업 화면과 같다([SetupMetaCard]·[SetupGrid]).
class SetupDetailPage extends ConsumerWidget {
  const SetupDetailPage({super.key, required this.trackId, required this.setupId});

  final String trackId;
  final String setupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(setupDetailProvider(setupId));
    final value = detail.valueOrNull;
    final String selectedGame = ref.watch(selectedGameProvider);
    final gameCode = value?.gameCode ?? selectedGame;
    final condition = value?.condition ?? kSetupConditionDry;
    return ListView(
      padding: pagePadding(context),
      children: [
        PageHeading(
          crumbs: [
            (label: gameYearLabelOf(gameCode), path: null),
            (label: _setupsLabel, path: setupsLocation(condition: condition)),
            if (value != null) (label: value.track.name, path: setupTrackLocation(trackId, condition: condition)),
          ],
          title: value == null ? _setupLabel : setupDetailTitle(value),
          countryCode: value?.track.countryCode,
          showFlag: value != null,
        ),
        const SizedBox(height: _headingGap),
        detail.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => e is ApiException && e.statusCode == _httpNotFound
              ? NotFoundState(
                  message: _notFoundMessage,
                  backLabel: _setupsLabel,
                  backPath: setupTrackLocation(trackId),
                )
              : ErrorRetry(
                  error: e,
                  fallbackMessage: _errorMessage,
                  onRetry: () => ref.invalidate(setupDetailProvider(setupId)),
                ),
          data: (data) => _SetupDetailBody(detail: data),
        ),
      ],
    );
  }
}

class _SetupDetailBody extends ConsumerWidget {
  const _SetupDetailBody({required this.detail});

  final SetupDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setOn = detail.setOn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetupMetaCard(
          items: [
            SetupMetaItem(label: _metaTeam, value: TeamNameCell(teamName: detail.teamName)),
            SetupMetaItem(label: _metaSession, value: Text(setupSessionLabel(detail.sessionType))),
            SetupMetaItem(
              label: _metaLapTime,
              value: Text(formatLapTime(detail.lapTimeMs), style: kTabularStyle),
            ),
            SetupMetaItem(label: _metaConditions, value: Text(detail.condition)),
            SetupMetaItem(label: _metaSteering, value: Text(detail.steering ?? kLapNoValueText)),
            SetupMetaItem(
              label: _metaDate,
              value: Text(setOn == null ? kLapNoValueText : _dateFormat.format(setOn)),
            ),
          ],
        ),
        const SizedBox(height: _cardGap),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('setup-source-link'),
            onPressed: () => ref.read(downloadLauncherProvider)(detail.sourceUrl),
            icon: const Icon(Icons.open_in_new),
            label: const Text(_viewOnSourceLabel),
          ),
        ),
        const SizedBox(height: _cardGap),
        if (detail.sections.isEmpty)
          const EmptyStateCard(message: _emptyMessage)
        else
          SetupGrid(groups: detail.sections),
      ],
    );
  }
}
