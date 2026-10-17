namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 실 DB(로컬 PostgreSQL의 테스트 DB <see cref="TestDatabase.Name"/>)를 쓰는 통합 테스트 클래스를 한 컬렉션으로 묶어 순서대로 실행한다.
/// 클래스마다 자기 호스트(<see cref="ApiFactory"/>)를 부팅하며 시작 시 마이그레이션·시드를 돌리는데,
/// 병렬로 부팅하면 빈 DB에서 트랙 시드(GameCode+GameTrackId unique)가 경합할 수 있다. 각 클래스의 fixture는 그대로 둔다.
/// 컬렉션 시작 시 <see cref="TestDatabaseFixture"/>가 한 번 테스트 DB를 마이그레이션하고 이전 실행 데이터를 비운다.
/// </summary>
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class DatabaseCollection : ICollectionFixture<TestDatabaseFixture>
{
    public const string Name = "Database";
}
