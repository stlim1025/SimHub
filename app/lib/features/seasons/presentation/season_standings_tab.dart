import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/ai_badge.dart';
import '../../../core/widgets/team_color_bar.dart';
import '../domain/season_models.dart';
import 'teammate_head_to_head_card.dart';

const String _note = '기록된 세션 기준입니다. 라운드 번호는 기록된 주말 순서라 게임과 다를 수 있습니다.';

const double _rowHeight = 44;
const double _driverMaxWidth = 220;

/// 이 폭 이상이면(넓은 화면) Drivers · Constructors 표를 나란히 둔다. 두 열의 폭 비율·간격.
const double _sideBySideWidth = 1100;
const int _driversFlex = 7;
const int _constructorsFlex = 5;
const double _columnGap = 20;
const double _sectionGap = 24;
const String _headToHeadTitle = 'Teammate Head-to-Head';

/// Standings 탭(docs/12 §8.3): 팀메이트 맞대결(있으면) + Drivers 표 + Constructors 표 + 집계 기준 안내.
/// 넓으면([_sideBySideWidth] 이상) Drivers 왼쪽, 오른쪽 열에 맞대결 → Constructors. 좁으면 맞대결 → Drivers → Constructors.
/// 좁은 화면에서는 표를 가로로 스크롤한다.
class SeasonStandingsTab extends StatelessWidget {
  const SeasonStandingsTab({super.key, required this.standings, this.headToHead});

  final SeasonStandings standings;

  /// 팀메이트 맞대결. 없으면(내 결과·팀메이트가 없음) 그리지 않는다.
  final TeammateHeadToHead? headToHead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h2h = headToHead;
    final headToHeadSection = h2h == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle(_headToHeadTitle),
              const SizedBox(height: 8),
              TeammateHeadToHeadCard(headToHead: h2h),
            ],
          );
    final drivers = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Drivers'),
        const SizedBox(height: 8),
        _DriversTable(drivers: standings.drivers),
      ],
    );
    final constructors = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Constructors'),
        const SizedBox(height: 8),
        _ConstructorsTable(constructors: standings.constructors),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= _sideBySideWidth
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: _driversFlex, child: drivers),
                    const SizedBox(width: _columnGap),
                    Expanded(
                      flex: _constructorsFlex,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (headToHeadSection != null) ...[headToHeadSection, const SizedBox(height: _sectionGap)],
                          constructors,
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (headToHeadSection != null) ...[headToHeadSection, const SizedBox(height: _sectionGap)],
                    drivers,
                    const SizedBox(height: _sectionGap),
                    constructors,
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Text(_note, style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted)),
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
    final headingStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: context.palette.textMuted);

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
