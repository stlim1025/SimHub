import 'dart:math' as math;

/// 페이지 표 하단 안내 문구. 예) `Showing 1 to 15 of 76`, 항목이 없으면 `Showing 0 of 0`.
/// [page]는 1부터 시작한다(순수 함수, 단위 테스트 대상).
String paginationLabel({required int page, required int pageSize, required int total}) {
  assert(page >= 1 && pageSize >= 1, 'page와 pageSize는 1 이상이어야 합니다.');
  if (total <= 0) {
    return 'Showing 0 of 0';
  }
  final to = math.min(page * pageSize, total);
  final from = math.min((page - 1) * pageSize + 1, to);
  return 'Showing $from to $to of $total';
}
