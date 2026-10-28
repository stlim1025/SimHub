import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/track_flag.dart';
import '../../sessions/domain/setup_display.dart';
import '../../sessions/presentation/setup_sections.dart';
import '../application/lap_detail_providers.dart';
import '../domain/car_setup.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';
import 'setup_diagnosis_card.dart';

const String _backTooltip = '랩 상세';
const String _fallbackTitle = 'Setup';
const String _titleSuffix = 'Setup';
const String _notFoundMessage = '찾을 수 없는 랩입니다.';
const String _notFoundBackLabel = 'Laps';
const String _lapsPath = '/laps';
const String _errorMessage = '셋업을 불러오지 못했어요.';
const String _emptyMessage = '이 랩에는 저장된 셋업이 없어요.';
const String _emptyActionLabel = '랩 상세로';

const int _httpNotFound = 404;
const double _titleFontSize = 22;
const double _titleFlagSize = 24;
const double _titleGap = 8;
const double _backGap = 4;
const double _sectionGap = 16;
const double _cardGap = 20;

/// 랩 셋업 화면(`/laps/:lapId/setup`, 랩 상세 Lap Details 카드의 View Setup): ← + `{트랙} Setup` 제목,
/// 묶음별 셋업 값 카드 격자(세션 셋업 화면과 같은 모양), 그 아래 셋업 진단. 셋업이 없으면 빈 상태, 없는 랩이면 404 상태.
class LapSetupPage extends ConsumerWidget {
  const LapSetupPage({super.key, required this.lapId});

  final String lapId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = LapDetailKey(lapId, LapCompareSelection.defaults);
    final detail = ref.watch(lapDetailProvider(key));
    return ListView(
      padding: pagePadding(context),
      children: [
        _Header(detail: detail.valueOrNull, onBack: () => context.go(lapDetailLocation(lapId))),
        const SizedBox(height: _sectionGap),
        detail.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => e is ApiException && e.statusCode == _httpNotFound
              ? const NotFoundState(message: _notFoundMessage, backLabel: _notFoundBackLabel, backPath: _lapsPath)
              : ErrorRetry(error: e, fallbackMessage: _errorMessage, onRetry: () => ref.invalidate(lapDetailProvider(key))),
          data: (data) => _SetupBody(detail: data),
        ),
      ],
    );
  }
}

class _SetupBody extends StatelessWidget {
  const _SetupBody({required this.detail});

  final LapDetail detail;

  @override
  Widget build(BuildContext context) {
    final setup = detail.car?.setup;
    final groups = setup == null ? const <SetupGroup>[] : setupGroups(setup);
    if (groups.isEmpty) {
      return EmptyStateCard(
        message: _emptyMessage,
        actionLabel: _emptyActionLabel,
        actionPath: lapDetailLocation(detail.lap.lapId),
      );
    }
    final carSetup = CarSetup.fromJsonOrNull(setup);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetupGrid(groups: groups),
        if (carSetup != null) ...[
          const SizedBox(height: _cardGap),
          SetupDiagnosisCard(setup: carSetup, trackName: detail.lap.trackName),
        ],
      ],
    );
  }
}

/// ← + 국기 + `{트랙} Setup`(랩 상세 제목과 같은 크기). 아직 모르면 `Setup`.
class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.onBack});

  final LapDetail? detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final value = detail;
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
            value == null ? _fallbackTitle : '${value.lap.trackName} $_titleSuffix',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
