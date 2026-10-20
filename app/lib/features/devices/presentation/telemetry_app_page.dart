import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/platform/download_launcher.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_notice.dart';
import '../../../core/widgets/section_card.dart';
import '../application/devices_providers.dart';
import '../data/agent_release_repository.dart';
import '../domain/agent_release.dart';
import 'connected_devices_card.dart';
import 'connection_status_card.dart';
import 'pairing_code_card.dart';

const double _sectionGap = 16;
const double _settingLabelWidth = 150;
const double _settingRowPadding = 10;
const double _downloadButtonHeight = 44;
const double _stepNumberWidth = 24;
const double _stepGap = 8;
const int _bytesPerMegabyte = 1024 * 1024;

const String _downloadTitle = 'SimHub Agent (Windows)';
const String _downloadLabel = 'Windows용 다운로드';
const String _openFailedText = 'Windows PC의 브라우저에서 이 화면을 열어 내려받아 주세요.';

final DateFormat _buildDateFormat = DateFormat('yyyy.MM.dd');

/// 설치 순서(압축 풀기 → 실행 → UDP 설정 → 연결 코드). 3·4단계는 아래 카드를 가리킨다.
const List<String> _installSteps = [
  '내려받은 SimHubAgent.zip의 압축을 모두 푼다(압축 파일 안에서 바로 실행하지 않는다).',
  'SimHub Agent.exe를 실행한다. Windows SmartScreen 경고가 뜨면 "추가 정보" → "실행"을 누른다.',
  'F1 25에서 아래 UDP 설정을 맞춘다.',
  '아래에서 연결 코드를 발급해 Agent 창에 입력하고 "연결"을 누른다.',
];

/// F1 25 UDP 텔레메트리 설정(docs/11 §7.3 ③). 포트는 Agent 기본값(20777)과 같다.
const List<(String, String)> _udpSettings = [
  ('UDP Telemetry', 'On'),
  ('UDP Format', '2025'),
  ('UDP Port', '20777'),
  ('UDP IP Address', 'Agent PC IP (Agent를 실행하는 PC의 IP 주소)'),
];

/// Telemetry App: Agent 설치·연결 코드·UDP 설정·연결된 PC·연결 상태를 한 화면에 모은다(docs/11 §7.3).
class TelemetryAppPage extends StatelessWidget {
  const TelemetryAppPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: pagePadding(context),
      children: [
        Text(
          'Telemetry App',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        const _DownloadCard(),
        const SizedBox(height: _sectionGap),
        const PairingCodeCard(),
        const SizedBox(height: _sectionGap),
        const _UdpSettingsCard(),
        const SizedBox(height: _sectionGap),
        const ConnectedDevicesCard(),
        const SizedBox(height: _sectionGap),
        const ConnectionStatusCard(showSetupAction: false),
      ],
    );
  }
}

/// ① 다운로드: Windows용 Agent zip 내려받기 + 설치 4단계. 빌드 정보(버전·날짜·크기)는 서버에 있을 때만 보인다.
class _DownloadCard extends ConsumerWidget {
  const _DownloadCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted);
    // 빌드 정보는 보조 정보라 로딩·실패를 따로 알리지 않고 없으면 숨긴다.
    final release = ref.watch(agentReleaseProvider).valueOrNull;

    return SectionCard(
      title: _downloadTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '게임을 하는 PC에서 실행하는 프로그램이다. F1 25 텔레메트리를 받아 랩 기록을 이 계정으로 보낸다.',
            style: muted,
          ),
          if (release != null) ...[
            const SizedBox(height: 8),
            Text(_releaseSummary(release), key: const ValueKey('agent-release-info'), style: muted),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: _downloadButtonHeight,
            child: FilledButton.icon(
              onPressed: () => _download(context, ref),
              icon: const Icon(Icons.download),
              label: const Text(_downloadLabel),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _installSteps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: _stepGap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _stepNumberWidth,
                    child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(child: Text(_installSteps[i])),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _download(BuildContext context, WidgetRef ref) {
    final opened = ref.read(downloadLauncherProvider)(agentDownloadUrlFor(AppConfig.apiBaseUrl));
    if (!opened) {
      AppToaster.of(context).show(_openFailedText);
    }
  }
}

/// "버전 e50ef1d-20261020 · 빌드 2026.10.20 · 68.1 MB". 빌드 날짜는 현지 날짜로 보인다.
String _releaseSummary(AgentRelease release) {
  final megabytes = (release.sizeBytes / _bytesPerMegabyte).toStringAsFixed(1);
  return '버전 ${release.version} · 빌드 ${_buildDateFormat.format(release.builtAt.toLocal())} · $megabytes MB';
}

/// ③ F1 25 UDP 설정 표.
class _UdpSettingsCard extends StatelessWidget {
  const _UdpSettingsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'F1 25 UDP 설정',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'F1 25의 Settings > Telemetry Settings에서 아래처럼 맞춘다.',
            style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {0: FixedColumnWidth(_settingLabelWidth)},
            border: TableBorder(horizontalInside: BorderSide(color: context.palette.border)),
            children: [
              for (final (label, value) in _udpSettings)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: _settingRowPadding),
                      child: Text(label, style: TextStyle(color: context.palette.textMuted)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: _settingRowPadding),
                      child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
