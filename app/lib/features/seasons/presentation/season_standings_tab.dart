import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ai_badge.dart';
import '../../../core/widgets/team_color_bar.dart';
import '../domain/season_models.dart';

const String _note = '기록된 세션 기준입니다. 라운드 번호는 기록된 주말 순서라 게임과 다를 수 있습니다.';

const double _rowHeight = 44;
const double _driverMaxWidth = 220;

/// Standings 탭(docs/12 §8.3): Drivers 표와 Constructors 표 + 집계 기준 안내.
/// 좁은 화면에서는 표를 가로로 스크롤한다.
class SeasonStandingsTab extends StatelessWidget {
  const SeasonStandingsTab({super.key, required this.standings});

  final SeasonStandings standings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Drivers'),
        const SizedBox(height: 8),
        _DriversTable(drivers: standings.drivers),
        const SizedBox(height: 24),
        const _SectionTitle('Constructors'),
        const SizedBox(height: 8),
        _ConstructorsTable(constructors: standings.constructors),
        const SizedBox(height: 16),
        Text(_note, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
  }
}

/// 카드 안의 표. 좁은 화면에서는 가로로 스크롤하고, 넓은 화면에서는 카드 폭을 채운다.
class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.columns, required this.rows});

  final List<DataColumn> columns;
  final List<DataRow> rows;

  @override
  Widget build(BuildContext context) {
    final headingStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.textMuted);

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingTextStyle: headingStyle,
              headingRowHeight: _rowHeight,
              dataRowMinHeight: _rowHeight,
              dataRowMaxHeight: _rowHeight,
              columns: columns,
              rows: rows,
            ),
          ),
        ),
      ),
    );
  }
}

class _DriversTable extends StatelessWidget {
  const _DriversTable({required this.drivers});

  final List<DriverStanding> drivers;

  @override
  Widget build(BuildContext context) {
    return _StandingsTable(
      columns: const [
        DataColumn(label: Text('Pos'), numeric: true),
        DataColumn(label: Text('Driver')),
        DataColumn(label: Text('Team')),
        DataColumn(label: Text('Wins'), numeric: true),
        DataColumn(label: Text('Podiums'), numeric: true),
        DataColumn(label: Text('Pts'), numeric: true),
      ],
      rows: [
        for (final driver in drivers)
          DataRow(
            color: driver.isPlayer ? const WidgetStatePropertyAll(AppColors.playerRow) : null,
            cells: [
              DataCell(Text('${driver.position}')),
              DataCell(_DriverCell(driver: driver)),
              DataCell(Text(driver.teamName)),
              DataCell(Text('${driver.wins}')),
              DataCell(Text('${driver.podiums}')),
              DataCell(Text('${driver.points}', style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
      ],
    );
  }
}

/// 팀 색 막대 + 이름 + (AI이면) AI 배지. 내 차는 이름을 굵게 한다.
class _DriverCell extends StatelessWidget {
  const _DriverCell({required this.driver});

  final DriverStanding driver;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _driverMaxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TeamColorBar(key: ValueKey('standings-team-bar-${driver.driverKey}'), colorHex: driver.teamColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              driver.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: driver.isPlayer ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
          ),
          if (driver.isAiControlled) ...[
            const SizedBox(width: 6),
            const AiBadge(),
          ],
        ],
      ),
    );
  }
}

class _ConstructorsTable extends StatelessWidget {
  const _ConstructorsTable({required this.constructors});

  final List<ConstructorStanding> constructors;

  @override
  Widget build(BuildContext context) {
    return _StandingsTable(
      columns: const [
        DataColumn(label: Text('Pos'), numeric: true),
        DataColumn(label: Text('Team')),
        DataColumn(label: Text('Wins'), numeric: true),
        DataColumn(label: Text('Pts'), numeric: true),
      ],
      rows: [
        for (final team in constructors)
          DataRow(
            cells: [
              DataCell(Text('${team.position}')),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TeamColorBar(key: ValueKey('constructor-team-bar-${team.teamId}'), colorHex: team.teamColor),
                    const SizedBox(width: 8),
                    Text(team.teamName),
                  ],
                ),
              ),
              DataCell(Text('${team.wins}')),
              DataCell(Text('${team.points}', style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
      ],
    );
  }
}
