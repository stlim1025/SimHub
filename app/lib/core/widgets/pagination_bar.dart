import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../util/pagination.dart';

/// 표 하단 페이지 바: `Showing 1 to 15 of 76` + 이전/다음. [page]는 1부터 시작한다.
/// 페이지 번호는 호출한 화면의 상태이며, 이 위젯은 요청만 [onPageChanged]로 알린다.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.onPageChanged,
  });

  final int page;
  final int pageSize;
  final int total;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final hasPrevious = page > 1;
    final hasNext = page * pageSize < total;

    return Row(
      children: [
        Expanded(
          child: Text(
            paginationLabel(page: page, pageSize: pageSize, total: total),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
        ),
        OutlinedButton(
          onPressed: hasPrevious ? () => onPageChanged(page - 1) : null,
          child: const Text('이전'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: hasNext ? () => onPageChanged(page + 1) : null,
          child: const Text('다음'),
        ),
      ],
    );
  }
}
