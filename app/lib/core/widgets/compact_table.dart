import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'fresh_highlight.dart';

/// 행 높이(docs/15 §2.1 "높이 44").
const double kCompactRowHeight = 44;

/// 머리줄 높이.
const double kCompactHeaderHeight = 36;

/// 열을 숨기기 시작하는 기본 콘텐츠 폭(세션 결과 표와 같다).
const double kCompactTableDefaultWidth = 600;

const double _cellGap = 12;
const double _headerLetterSpacing = 0.6;
const EdgeInsets _rowPadding = EdgeInsets.symmetric(horizontal: 16);
const EdgeInsets _footerPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

/// 촘촘한 표의 한 열. [width]를 주면 고정 폭, 아니면 [flex] 비율로 나눈다. [compactHidden]이면 좁은 화면에서 숨긴다.
class CompactColumn<T> {
  const CompactColumn({
    required this.label,
    required this.cell,
    this.header,
    this.flex = 1,
    this.width,
    this.compactHidden = false,
    this.alignment = Alignment.centerLeft,
  });

  /// 머리글(대문자로 보인다). [header]를 주면 그 위젯을 대신 쓴다(아이콘 머리글 등).
  final String label;
  final Widget? header;
  final Widget Function(T row) cell;
  final int flex;
  final double? width;
  final bool compactHidden;
  final AlignmentGeometry alignment;
}

/// F1Laps 모양의 촘촘한 표(docs/15 §2.1, `DataTable` 대신): 작은 대문자 흐린 머리글 + 표면보다 살짝 어두운 머리줄,
/// 높이 44 행 + 얇은 구분선, 마우스를 올리면 강조, 행 전체 클릭. 위젯이 받은 폭이 [compactWidth] 미만이면
/// [CompactColumn.compactHidden] 열을 숨긴다(넘치지 않게 칸 글자는 말줄임). [footer](페이지 바 등)는 카드 맨 아래에 붙는다.
class CompactTable<T> extends StatelessWidget {
  const CompactTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.isHighlighted,
    this.isFresh,
    this.rowKey,
    this.footer,
    this.compactWidth = kCompactTableDefaultWidth,
  });

  final List<CompactColumn<T>> columns;
  final List<T> rows;
  final ValueChanged<T>? onRowTap;

  /// 참이면 그 행을 강조 배경(`AppColors.playerRow`)으로 칠한다(예: 지금 보는 랩).
  final bool Function(T row)? isHighlighted;

  /// 참이면 그 행을 막 들어온 행으로 잠깐 강조한다([FreshHighlight], D-50).
  final bool Function(T row)? isFresh;

  /// 행 위젯의 키(테스트·상태 보존용).
  final Key Function(T row)? rowKey;
  final Widget? footer;
  final double compactWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactWidth;
        final visible = [
          for (final column in columns)
            if (!(compact && column.compactHidden)) column,
        ];
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderRow<T>(columns: visible),
              for (final row in rows) ...[
                const Divider(height: 1),
                _BodyRow<T>(
                  key: rowKey?.call(row),
                  row: row,
                  columns: visible,
                  highlighted: isHighlighted?.call(row) ?? false,
                  fresh: isFresh?.call(row) ?? false,
                  onTap: onRowTap == null ? null : () => onRowTap!(row),
                ),
              ],
              if (footer != null) ...[
                const Divider(height: 1),
                Padding(padding: _footerPadding, child: footer),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 열 하나의 칸(고정 폭 또는 비율).
Widget _cellBox<T>(CompactColumn<T> column, Widget child) {
  final aligned = Align(alignment: column.alignment, child: child);
  final width = column.width;
  return width == null ? Expanded(flex: column.flex, child: aligned) : SizedBox(width: width, child: aligned);
}

/// 칸 사이에 간격을 끼운 줄.
List<Widget> _withGaps(List<Widget> cells) => [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) const SizedBox(width: _cellGap),
        cells[i],
      ],
    ];

class _HeaderRow<T> extends StatelessWidget {
  const _HeaderRow({required this.columns});

  final List<CompactColumn<T>> columns;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: _headerLetterSpacing,
        );
    return Container(
      height: kCompactHeaderHeight,
      color: palette.tableHeader,
      padding: _rowPadding,
      child: Row(
        children: _withGaps([
          for (final column in columns)
            _cellBox(
              column,
              column.header ?? Text(column.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.clip, style: style),
            ),
        ]),
      ),
    );
  }
}

class _BodyRow<T> extends StatelessWidget {
  const _BodyRow({
    super.key,
    required this.row,
    required this.columns,
    required this.highlighted,
    required this.fresh,
    required this.onTap,
  });

  final T row;
  final List<CompactColumn<T>> columns;
  final bool highlighted;
  final bool fresh;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = _rowBody();
    // 읽기 도구에는 칸 조각이 아니라 눌러 여는 한 줄(버튼)로 알린다.
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        selected: highlighted,
        child: fresh ? FreshHighlight(child: body) : body,
      ),
    );
  }

  Widget _rowBody() {
    return Material(
      color: highlighted ? AppColors.playerRow : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.rowHover,
        child: Container(
          height: kCompactRowHeight,
          padding: _rowPadding,
          child: Row(
            children: _withGaps([for (final column in columns) _cellBox(column, column.cell(row))]),
          ),
        ),
      ),
    );
  }
}
