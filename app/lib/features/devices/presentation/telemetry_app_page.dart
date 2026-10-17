import 'package:flutter/material.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/theme/app_colors.dart';
import 'connected_devices_card.dart';
import 'connection_status_card.dart';
import 'pairing_code_card.dart';
import 'section_card.dart';

const double _sectionGap = 16;
const double _settingLabelWidth = 150;
const double _settingRowPadding = 10;

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
      padding: kPagePadding,
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

/// ① 다운로드. 설치 파일(P11) 전까지는 준비 중 안내와 개발용 실행 방법만 보여준다.
class _DownloadCard extends StatelessWidget {
  const _DownloadCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: '다운로드',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('설치 파일 준비 중'),
          const SizedBox(height: 12),
          Text(
            '개발용으로는 agent/src/SimCenter.Agent.Cli 폴더에서 아래 명령으로 연결할 수 있어요.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: SelectableText('dotnet run -- pair <코드>'),
            ),
          ),
        ],
      ),
    );
  }
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
            'F1 25의 Settings > Telemetry Settings에서 아래처럼 맞춰 주세요.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {0: FixedColumnWidth(_settingLabelWidth)},
            border: const TableBorder(horizontalInside: BorderSide(color: AppColors.border)),
            children: [
              for (final (label, value) in _udpSettings)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: _settingRowPadding),
                      child: Text(label, style: const TextStyle(color: AppColors.textMuted)),
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
