import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/ranking/application/ranking_providers.dart';

void main() {
  test('shouldApplyHubSnapshot_OnlyForMonthlyOfSameTrack', () {
    const q = RankingQuery(trackId: 't1', period: 'monthly');
    expect(shouldApplyHubSnapshot(q, {'trackId': 't1'}), isTrue);
    expect(shouldApplyHubSnapshot(q, {'trackId': 't2'}), isFalse);
    expect(shouldApplyHubSnapshot(const RankingQuery(trackId: 't1', period: 'daily'), {'trackId': 't1'}), isFalse);
  });

  test('RankingQuery_EqualityIsByValue', () {
    const a = RankingQuery(trackId: 't1', period: 'monthly');
    const b = RankingQuery(trackId: 't1', period: 'monthly');

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const RankingQuery(trackId: 't1', period: 'daily')));
    expect(a, isNot(const RankingQuery(trackId: 't2', period: 'monthly')));
  });
}
