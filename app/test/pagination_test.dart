import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/core/util/pagination.dart';

void main() {
  group('paginationLabel', () {
    test('첫 페이지', () {
      expect(paginationLabel(page: 1, pageSize: 15, total: 76), 'Showing 1 to 15 of 76');
    });

    test('중간 페이지', () {
      expect(paginationLabel(page: 2, pageSize: 15, total: 76), 'Showing 16 to 30 of 76');
    });

    test('마지막 페이지는 total에서 끝난다', () {
      expect(paginationLabel(page: 6, pageSize: 15, total: 76), 'Showing 76 to 76 of 76');
    });

    test('한 페이지에 다 들어가면 1부터 total까지', () {
      expect(paginationLabel(page: 1, pageSize: 15, total: 4), 'Showing 1 to 4 of 4');
    });

    test('항목이 없으면 0 of 0', () {
      expect(paginationLabel(page: 1, pageSize: 15, total: 0), 'Showing 0 of 0');
    });

    test('범위를 벗어난 페이지도 시작이 끝을 넘지 않는다', () {
      expect(paginationLabel(page: 9, pageSize: 15, total: 76), 'Showing 76 to 76 of 76');
    });
  });
}
