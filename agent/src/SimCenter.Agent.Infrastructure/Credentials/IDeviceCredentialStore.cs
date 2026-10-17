namespace SimCenter.Agent.Infrastructure.Credentials;

/// <summary>
/// 계정 연결 시 서버가 1회 발급한 장치 키의 보관소. 키는 평문으로 디스크·설정 파일에 남기지 않는다.
/// </summary>
public interface IDeviceCredentialStore
{
    /// <summary>저장된 장치 키를 읽는다. 키가 없거나 읽을 수 없으면(손상 등) null — 미연결로 취급한다.</summary>
    string? Load();

    /// <summary>장치 키를 저장한다(기존 키는 덮어쓴다). 저장 후 <see cref="Changed"/>가 발생한다.</summary>
    void Save(string deviceKey);

    /// <summary>저장된 장치 키를 지운다(연결 해제). 지운 후 <see cref="Changed"/>가 발생한다.</summary>
    void Clear();

    /// <summary>키가 저장되거나 지워질 때 발생한다. 호출 스레드에서 동기 실행되므로 핸들러는 가벼워야 한다.</summary>
    event EventHandler? Changed;
}
