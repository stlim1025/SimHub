import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/track_flag.dart';
import '../../lap_detail/presentation/detail_list.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/presentation/lap_cells.dart';
import '../application/sessions_providers.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import '../domain/setup_display.dart';
import 'session_widgets.dart';

const String _backTooltip = '세션 결과';
const String _fallbackTitle = 'Setup';
const String _titleSuffix = 'Setup';
const String _notFoundMessage = '찾을 수 없는 세션입니다.';
const String _notFoundBackLabel = 'Sessions';
const String _sessionsPath = '/sessions';
const String _errorMessage = '셋업을 불러오지 못했어요.';
const String _emptyMessage = '이 세션에는 저장된 셋업이 없어요.';
const String _emptyActionLabel = '세션 결과로';

const String _metaTeam = 'Team';
const String _metaSession = 'Session';
const String _metaLapTime = 'Lap Time';
const String _metaConditions = 'Conditions';
const String _metaDate = 'Date';

const int _httpNotFound = 404;
const double _titleFontSize = 22;
const double _titleFlagSize = 24;
const double _titleGap = 8;
const double _backGap = 4;
const double _sectionGap = 16;
const double _cardGap = 20;
const double _metaPadding = 20;
const double _metaSpacing = 32;
const double _metaRunSpacing = 12;
const double _metaLabelGap = 2;
const double _metaIconGap = 6;

/// 콘텐츠 폭이 이 값 이상이면 셋업 카드 3열.
const double kSetupThreeColumnWidth = 1100;

/// 콘텐츠 폭이 이 값 이상이면 셋업 카드 2열(미만은 1열).
const double kSetupTwoColumnWidth = 640;

const int _threeColumns = 3;
const int _twoColumns = 2;
const int _oneColumn = 1;

final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

/// 세션 셋업 화면(`/sessions/:sessionId/setup`, F1Laps 셋업 페이지 모양): ← + `{트랙} Setup ({날씨})` 제목,
/// Team · Session · Lap Time · Conditions · Date 요약 줄, 그 아래 묶음(Aerodynamics·Transmission·…)별 카드 격자.
/// 데이터는 세션 상세([sessionDetailProvider])를 그대로 쓴다. 셋업이 없으면 빈 상태, 없는 세션이면 404 상태.
class SessionSetupPage extends ConsumerWidget {
  const SessionSetupPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sessionDetailProvider(sessionId));
    return ListView(
      padding: pagePadding(context),
      children: [
        _Header(header: detail.valueOrNull?.header, onBack: () => context.go(sessionLocation(sessionId))),
        const SizedBox(height: _sectionGap),
        detail.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => _isNotFound(e)
              ? const NotFoundState(message: _notFoundMessage, backLabel: _notFoundBackLabel, backPath: _sessionsPath)
              : ErrorRetry(
                  error: e,
                  fallbackMessage: _errorMessage,
                  onRetry: () => ref.invalidate(sessionDetailProvider(sessionId)),
                ),
          data: (data) => _SetupBody(detail: data),
        ),
      ],
    );
  }

  static bool _isNotFound(Object error) => error is ApiException && error.statusCode == _httpNotFound;
}

/// 셋업 화면 제목: `Bahrain Setup (Clear)`. 날씨를 모르면 괄호를 뺀다(순수 함수).
String setupPageTitle(SessionDetailHeader header) {
  final conditions = weatherLabel(header.weather);
  final base = '${header.trackName} $_titleSuffix';
  return conditions == null ? base : '$base ($conditions)';
}

/// ← + 국기 + 한 줄 제목(22px, 랩 상세·세션 상세 제목과 같은 크기). 아직 모르면 `Setup`.
class _Header extends StatelessWidget {
  const _Header({required this.header, required this.onBack});

  final SessionDetailHeader? header;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final value = header;
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: _titleFontSize, fontWeight: FontWeight.bold);
    return Row(
      children: [
        IconButton(tooltip: _backTooltip, icon: const Icon(Icons.arrow_back), onPressed: onBack),
        const SizedBox(width: _backGap),
        if (value != null) ...[
          TrackFlag(countryCode: value.countryCode, size: _titleFlagSize),
          const SizedBox(width: _titleGap),
        ],
        Expanded(
          child: Text(
            value == null ? _fallbackTitle : setupPageTitle(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// 요약 줄 + 셋업 카드 격자. 셋업이 없거나 보일 값이 없으면 빈 상태 카드.
class _SetupBody extends StatelessWidget {
  const _SetupBody({required this.detail});

  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final setup = detail.setup;
    final groups = setup == null ? const <SetupGroup>[] : setupGroups(setup);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetaStrip(detail: detail),
        const SizedBox(height: _cardGap),
        if (groups.isEmpty)
          EmptyStateCard(
            message: _emptyMessage,
            actionLabel: _emptyActionLabel,
            actionPath: sessionLocation(detail.header.sessionId),
          )
        else
          _SetupGrid(groups: groups),
      ],
    );
  }
}

/// Team · Session · Lap Time · Conditions · Date 요약(F1Laps 셋업 페이지 머리의 정보 줄). 좁으면 여러 줄로 감긴다.
class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.detail});

  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final header = detail.header;
    final team = header.myTeam;
    final lapTime = detail.myBestLap?.lapTimeMs ?? header.myBestLapTimeMs;
    final weather = header.weather;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(_metaPadding),
        child: Wrap(
          spacing: _metaSpacing,
          runSpacing: _metaRunSpacing,
          children: [
            _MetaItem(
              label: _metaTeam,
              value: team == null
                  ? const Text(kNoValueText)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TeamDot(colorHex: team.color),
                        const SizedBox(width: _metaIconGap),
                        Text(team.name),
                      ],
                    ),
            ),
            _MetaItem(
              label: _metaSession,
              value: Text(sessionKindName(header.sessionKind, sprintWeekend: header.isSprintWeekend)),
            ),
            _MetaItem(
              label: _metaLapTime,
              value: Text(lapTime == null ? kNoValueText : formatLapTime(lapTime), style: kTabularStyle),
            ),
            _MetaItem(
              label: _metaConditions,
              value: weather == null
                  ? const Text(kNoValueText)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(weatherIconOf(weather), size: kWeatherIconSize, color: context.palette.textMuted),
                        const SizedBox(width: _metaIconGap),
                        Text(weatherLabel(weather)!),
                      ],
                    ),
            ),
            _MetaItem(label: _metaDate, value: Text(_dateFormat.format(header.classifiedAt.toLocal()))),
          ],
        ),
      ),
    );
  }
}

/// 요약 한 칸: 위 흐린 이름표 + 아래 굵은 값. `setup-meta-{이름표}` 키를 갖는다.
class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: ValueKey('setup-meta-$label'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall?.copyWith(color: context.palette.textMuted)),
        const SizedBox(height: _metaLabelGap),
        DefaultTextStyle.merge(style: const TextStyle(fontWeight: FontWeight.bold), child: value),
      ],
    );
  }
}

/// 셋업 묶음 카드 격자: 넓으면 3열, 중간 2열, 좁으면 1열. 한 줄의 카드는 같은 폭·같은 높이.
class _SetupGrid extends StatelessWidget {
  const _SetupGrid({required this.groups});

  final List<SetupGroup> groups;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = setupGridColumns(constraints.maxWidth);
        final cards = [for (final group in groups) _SetupGroupCard(group: group)];
        if (columns == _oneColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: _cardGap),
                cards[i],
              ],
            ],
          );
        }
        final rows = <Widget>[
          for (var start = 0; start < cards.length; start += columns)
            EqualHeightRow(
              gap: _cardGap,
              children: [
                for (var i = start; i < start + columns; i++) i < cards.length ? cards[i] : const SizedBox.shrink(),
              ],
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: _cardGap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// 콘텐츠 폭 → 셋업 카드 열 수(순수 함수).
int setupGridColumns(double width) => width >= kSetupThreeColumnWidth
    ? _threeColumns
    : width >= kSetupTwoColumnWidth
        ? _twoColumns
        : _oneColumn;

/// 셋업 묶음 하나: 카드 제목 + 이름표(왼쪽)·값(오른쪽, 굵게) 줄 목록. `setup-group-{제목}` 키를 갖는다.
class _SetupGroupCard extends StatelessWidget {
  const _SetupGroupCard({required this.group});

  final SetupGroup group;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: ValueKey('setup-group-${group.title}'),
      title: group.title,
      child: DetailList(items: [for (final item in group.items) DetailItem(item.label, text: item.value)]),
    );
  }
}
