import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import 'track_flag.dart';

/// 메뉴 폭(docs/15 §2.2 "폭 약 280").
const double kTrackMenuWidth = 280;

/// 메뉴 최대 높이 = 화면 높이의 이 비율.
const double kTrackMenuMaxHeightFactor = 0.8;

const double _titleFlagSize = 28;
const double _titleGap = 10;
const double _titleIconGap = 4;
const double _titleRadius = 8;
const EdgeInsets _titlePadding = EdgeInsets.symmetric(horizontal: 4, vertical: 4);
const String _pickerSemanticLabel = '트랙 선택';
const double _checkIconSize = 18;

/// 트랙 메뉴의 한 줄(기능 모델과 떨어진 표시용 값).
@immutable
class TrackChoice {
  const TrackChoice({required this.id, required this.name, this.countryCode});

  final String id;
  final String name;

  /// ISO 3166-1 alpha-2. 모르면 null(회색 원).
  final String? countryCode;

  @override
  bool operator ==(Object other) =>
      other is TrackChoice && other.id == id && other.name == name && other.countryCode == countryCode;

  @override
  int get hashCode => Object.hash(id, name, countryCode);
}

/// 트랙 메뉴(D-43·D-47, docs/15 §2.2, Laps·Leaderboard 공용). 제목(국기 + 이름 + ⇅)을 누르면 제목 아래에 붙어 열리는 목록:
/// 원형 국기 + 트랙 이름, 받은 순서 그대로(= `GET /tracks`의 캘린더 순서), 고른 트랙은 강조색. 목록이 길면 스크롤한다.
class TrackPicker extends StatelessWidget {
  const TrackPicker({
    super.key,
    required this.tracks,
    required this.selected,
    required this.onSelected,
    this.placeholder = 'Select track',
    this.textStyle,
    this.showFlags = true,
    this.semanticLabel = _pickerSemanticLabel,
  });

  /// 메뉴 항목(이 순서대로 보인다). 비어 있으면 메뉴가 열리지 않는다.
  final List<TrackChoice> tracks;

  /// 제목에 보일 트랙. null이면 [placeholder](국기 없음).
  final TrackChoice? selected;
  final ValueChanged<TrackChoice> onSelected;
  final String placeholder;

  /// false면 국기를 그리지 않는다(같은 모양의 시즌 메뉴, docs/15 §12).
  final bool showFlags;

  /// 제목 버튼의 읽기 도구 이름.
  final String semanticLabel;

  /// 제목 글자 모양. 기본은 `headlineSmall` 굵게.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final maxHeight = MediaQuery.sizeOf(context).height * kTrackMenuMaxHeightFactor;
    return MenuAnchor(
      // 폭 제한(280)이 목록에 그대로 걸리게 한다(기본값은 가로 제약을 풀어 내용 폭이 된다).
      crossAxisUnconstrained: false,
      // 열린 목록 밖을 누르면 목록만 닫는다. 기본값(false)은 그 누름이 아래 위젯까지 전달돼
      // Laps 표 행이 함께 눌려 랩 상세로 이동했다(D-50 작업 중 보고된 메뉴 관통 버그).
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
        minimumSize: const WidgetStatePropertyAll(Size(kTrackMenuWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(kTrackMenuWidth, maxHeight)),
      ),
      menuChildren: [
        for (final track in tracks)
          _TrackMenuItem(
            key: ValueKey('track-option-${track.id}'),
            track: track,
            selected: track.id == selected?.id,
            showFlag: showFlags,
            onPressed: () => onSelected(track),
          ),
      ],
      builder: (context, controller, _) => _PickerTitle(
        selected: selected,
        placeholder: placeholder,
        textStyle: textStyle,
        showFlag: showFlags,
        semanticLabel: semanticLabel,
        onTap: tracks.isEmpty ? null : () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _PickerTitle extends StatelessWidget {
  const _PickerTitle({
    required this.selected,
    required this.placeholder,
    required this.textStyle,
    required this.showFlag,
    required this.semanticLabel,
    required this.onTap,
  });

  final TrackChoice? selected;
  final String placeholder;
  final TextStyle? textStyle;
  final bool showFlag;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final track = selected;
    final style = textStyle ?? Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: InkWell(
        key: const ValueKey('track-picker'),
        borderRadius: BorderRadius.circular(_titleRadius),
        onTap: onTap,
        child: Padding(
          padding: _titlePadding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track != null && showFlag) ...[
                TrackFlag(countryCode: track.countryCode, size: _titleFlagSize),
                const SizedBox(width: _titleGap),
              ],
              Flexible(
                child: Text(
                  track?.name ?? placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              const SizedBox(width: _titleIconGap),
              Icon(Icons.unfold_more, color: context.palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackMenuItem extends StatelessWidget {
  const _TrackMenuItem({
    super.key,
    required this.track,
    required this.selected,
    required this.showFlag,
    required this.onPressed,
  });

  final TrackChoice track;
  final bool selected;
  final bool showFlag;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // 줄 전체가 메뉴 폭을 채워야 마우스를 올린 강조가 끝까지 칠해진다.
    // 고른 트랙은 색만이 아니라 ✓ 아이콘·선택 상태로도 알린다. 글자색은 표면 대비가 맞는 링크 색.
    final palette = context.palette;
    return Semantics(
      selected: selected,
      child: SizedBox(
        width: kTrackMenuWidth,
        child: MenuItemButton(
          leadingIcon: showFlag ? TrackFlag(countryCode: track.countryCode) : null,
          trailingIcon: selected ? Icon(Icons.check, size: _checkIconSize, color: palette.link) : null,
          autofocus: selected,
          onPressed: onPressed,
          child: Text(
            track.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? palette.link : palette.textPrimary,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
