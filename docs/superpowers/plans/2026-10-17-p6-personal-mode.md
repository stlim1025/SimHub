# P6 개인 모드 전환 + 웹 셸 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 카페 모델(매장·좌석·체크인)을 걷어내고, 내 PC의 Agent를 1회용 코드로 내 계정에 연결해 랩을 쌓으며, F1Laps 스타일 사이드바 웹 셸(Dashboard · Laps · Leaderboard · Telemetry App)을 만든다.

**Architecture:** 백엔드는 Clean Architecture를 유지한 채 `AgentDevice`·`AgentPairingCode`를 추가하고, 기존 `X-Agent-Key` 인증이 좌석 대신 장치를 가리키게 바꾼다. Agent는 DPAPI로 장치 키를 보관하고 키 유무·401에 따라 업로드를 멈추고 재개한다. Flutter는 GoRouter `ShellRoute` 위에 반응형 사이드바를 얹는다.

**Tech Stack:** .NET 10 · ASP.NET Core 10 · EF Core 10 + Npgsql · SignalR · xUnit / .NET 10 Agent(WPF Tray) · `System.Security.Cryptography.ProtectedData` / Flutter 3.41 · Riverpod 2 · GoRouter 14 · Dio · Material3

**Spec:** [docs/11-personal-mode.md](../../11-personal-mode.md)

## Global Constraints

- 헌장: 시간·랜덤은 추상화(`IClock`, `IIdGenerator`, 신규 `IRandomSource`). `DateTime.Now`·정적 난수 직접 사용 금지. Magic Number 금지(아래 값은 이름 붙은 상수로).
- 연결 코드: 문자 집합 `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, 길이 8, 표시 `XXXX-XXXX`, 유효 10분, 1회용, 해시(SHA-256)로만 저장, 충돌 시 최대 3회 재생성.
- 장치 키: 32바이트 난수 → base64url(패딩 없음, 43자), 응답에서 1회만 반환, 서버에는 해시만.
- 장치 이름: 앞뒤 공백 제거, 1~50자, 비면 `"Windows PC"`.
- 오류 문구 고정: 연결 실패 `"유효하지 않거나 만료된 코드입니다."`(만료·사용·무효·없음 공통), 해제된 장치 `"연결이 해제된 장치입니다."`.
- 요청 제한: `POST /api/v1/agent/pair` IP당 분당 10회, `POST /api/v1/me/agent-pairing-codes` 사용자당 분당 10회, 초과 시 429.
- `LastSeenAt` 쓰기 간격 1분. Connection Status "수신 중" 기준 5분.
- 랭킹 타임존: 설정 `Ranking:TimeZoneId`, 기본 `Asia/Seoul`, 시작 시 검증.
- Agent: 설정 `ServerBaseUrl`(기본 `http://localhost:5284`), 연결 API `{ServerBaseUrl}/api/v1/agent/pair`, 허브 `{ServerBaseUrl}/hubs/telemetry`, 키 파일 `%LOCALAPPDATA%\SimCenter\Agent\device.key`(DPAPI `CurrentUser`).
- 연결 코드·장치 키 원문은 로그에 남기지 않는다.
- API: `/api/v1`, 응답 camelCase, 오류는 RFC 7807(기존 `ExceptionHandlingMiddleware` 매핑: `ValidationException`→400, `ForbiddenException`→403, `NotFoundException`→404).
- Flutter: 색은 `AppColors` 토큰으로만. 셸 기준 폭 900, 사이드바 폭 220. Laps 페이지 크기 15.
- 테스트 관례: xUnit + `Assert`, 테스트 파일마다 private nested Fake. Flutter는 `flutter_test`.
- 커밋: 한국어 conventional commit + 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **실행 환경(이 PC):** Claude 앱을 재시작하기 전까지 셸이 옛 환경 변수를 물려받는다. 모든 `dotnet`·`flutter` 명령 앞에
  `$env:DOTNET_ROOT='C:\Program Files\dotnet'; $env:TEMP='C:\Temp'; $env:TMP='C:\Temp';`를 붙인다.
  빌드 전에 실행 중인 backend·agent·app 터미널 탭을 멈춘다(실행 파일 잠금). 통합 테스트는 로컬 PostgreSQL과 user-secrets(설정 완료)를 쓴다.
- **스펙과 다른 점 1건:** 스펙 §3.4는 마이그레이션 1건이지만, EF Core 9+는 모델과 마이그레이션이 어긋나면 `MigrateAsync`에서 예외를 던진다. 각 태스크가 끝날 때 테스트가 초록이도록 **추가용 `AddAgentDevices`(Task 3)와 전환용 `PersonalMode`(Task 4) 2건**으로 나눈다. 데이터 삭제·테이블 삭제는 모두 `PersonalMode`에 있다.

## Review Focus

1. **랩이 하나도 없는 새 사용자** — `/me/tracks`가 빈 배열이고, Dashboard·Laps가 오류 없이 빈 상태 안내를 보여야 한다. → Task 5 `GetMyTracks_NoLaps_ReturnsEmpty`, Task 11 `LapsPage_Empty_ShowsGuide`.
2. **Leaderboard에서 일·연 기간을 보는 중 실시간 월별 스냅샷 도착** — 월별 데이터로 덮어쓰면 안 되고, 해당 기간을 REST로 다시 읽어야 한다. → Task 10 `shouldApplyHubSnapshot_OnlyForMonthlyOfSameTrack`.
3. **웹에서 연결을 해제한 뒤 Agent가 다시 접속(401)** — 업로드를 멈추되 Outbox에 쌓인 이벤트는 지우지 않아야 한다(다시 연결하면 올라감). → Task 7 `Unauthorized_StopsUploading_AndKeepsOutboxItems`.
4. **만료 시각과 정확히 같은 순간에 코드 입력** — 만료로 처리한다(`ExpiresAt > now`만 유효). → Task 1 `Pair_AtExactExpiry_IsRejected`.
5. **코드 남은 시간이 0이 된 화면** — 음수 시간을 보여 주지 말고 "만료됨"과 재발급 버튼을 보여야 한다. → Task 12 `formatRemaining_ZeroOrNegative_IsExpired`.

---

## File Structure

```
backend/src/SimCenter.Domain/Entities/        AgentDevice.cs, AgentPairingCode.cs (신규) · Lap.cs, User.cs (수정) · Store/SimRig/DrivingSession.cs (삭제)
backend/src/SimCenter.Domain/Enums/           SessionStatus.cs (삭제)
backend/src/SimCenter.Application/
  Common/Interfaces/                          IRandomSource, ITransactionRunner, IAgentDeviceRepository, IAgentPairingCodeRepository, IRankingTimeZoneProvider (신규)
                                              ISimRigRepository, IDrivingSessionRepository, IStoreRepository (삭제)
  AgentDevices/                               PairingCodeFormat, DeviceKeyFormat, AgentDeviceDtos, IAgentPairingService, AgentPairingService,
                                              IAgentDeviceService, AgentDeviceService (신규)
  Rankings/                                   MyLapsSort, MyTrackSummaryRow (신규) · RankingDtos, IRankingService, RankingService (수정)
  Telemetry/                                  TelemetryContracts, ITelemetryIngestService, TelemetryIngestService (수정)
  Sessions/                                   (폴더 삭제)
backend/src/SimCenter.Infrastructure/
  Common/CryptoRandomSource.cs, Configuration/RankingOptions.cs, Configuration/ConfiguredRankingTimeZoneProvider.cs (신규)
  Persistence/Configurations/                 AgentDeviceConfiguration, AgentPairingCodeConfiguration (신규) · LapConfiguration (수정)
                                              Store/SimRig/DrivingSessionConfiguration (삭제)
  Persistence/Repositories/                   AgentDeviceRepository, AgentPairingCodeRepository (신규) · LapRepository (수정)
                                              SimRig/DrivingSession/StoreRepository (삭제)
  Persistence/Migrations/                     AddAgentDevices, PersonalMode (신규)
  Identity/AgentApiKeyAuthenticationHandler.cs, Persistence/Seed/DbSeeder.cs, Persistence/AppDbContext.cs, DependencyInjection.cs (수정)
backend/src/SimCenter.Api/
  Common/ClaimsPrincipalExtensions.cs, RateLimiting/RateLimitPolicies.cs (신규)
  Controllers/AgentPairingController.cs, Controllers/MyAgentDevicesController.cs (신규) · MeController.cs (수정) · SessionsController.cs (삭제)
  Hubs/TelemetryHub.cs, Program.cs, appsettings.json (수정)
backend/tests/SimCenter.Application.Tests/    AgentDevices/*, Rankings/RankingServiceTests, Telemetry/TelemetryIngestServiceTests (수정) · Sessions/ (삭제)
backend/tests/SimCenter.Api.IntegrationTests/ ApiFactory.cs, TestApi.cs, AgentPairingE2ETests.cs (신규) · TelemetryIngestE2ETests.cs (수정)

agent/src/SimCenter.Agent.Core/Telemetry/Events/    TelemetryEnvelope, AgentIdentity (수정)
agent/src/SimCenter.Agent.Infrastructure/
  Credentials/                                IDeviceCredentialStore, DpapiDeviceCredentialStore (신규)
  Configuration/                              AgentOptions (수정), AgentEndpoints (신규)
  Upload/                                     ITelemetryHubSession, SignalRTelemetryHubSessionFactory, UploadState, UploadStatusTracker,
                                              UnauthorizedDetector (신규) · TelemetryUploadService (수정)
  Pairing/                                    IAgentPairingClient, AgentPairingClient, PairOutcome, PairCommand (신규)
  Sinks/OutboxTelemetrySink, Sinks/LoggingTelemetrySink, DependencyInjection (수정)
agent/src/SimCenter.Agent.Cli/                Program.cs, appsettings.json (수정)
agent/src/SimCenter.Agent.Tray/               MainWindow.xaml(.cs), App.xaml.cs, appsettings.json (수정)

app/lib/core/theme/app_colors.dart, core/shell/app_shell.dart, core/shell/nav_items.dart, core/util/relative_time.dart,
    core/util/pagination.dart, core/time/clock_provider.dart (신규)
app/lib/features/dashboard/presentation/dashboard_page.dart (신규)
app/lib/features/ranking/presentation/leaderboard_page.dart (신규) · home_page.dart, today_ranking_page.dart (삭제)
app/lib/features/laps/presentation/laps_page.dart, track_laps_page.dart (신규) · my_laps_page.dart (삭제)
app/lib/features/devices/{domain,data,application,presentation}/... (신규)
app/lib/features/session/ (폴더 삭제)
```

---

### Task 1: 연결 코드·장치 유스케이스 (Domain + Application, 순수 로직)

**Files:**
- Create: `backend/src/SimCenter.Domain/Entities/AgentDevice.cs`, `backend/src/SimCenter.Domain/Entities/AgentPairingCode.cs`
- Create: `backend/src/SimCenter.Application/Common/Interfaces/IRandomSource.cs`, `ITransactionRunner.cs`, `IAgentDeviceRepository.cs`, `IAgentPairingCodeRepository.cs`
- Create: `backend/src/SimCenter.Application/AgentDevices/PairingCodeFormat.cs`, `DeviceKeyFormat.cs`, `AgentDeviceDtos.cs`, `IAgentPairingService.cs`, `AgentPairingService.cs`, `IAgentDeviceService.cs`, `AgentDeviceService.cs`
- Modify: `backend/src/SimCenter.Application/DependencyInjection.cs` (두 서비스 Scoped 등록)
- Create: `backend/src/SimCenter.Infrastructure/Common/CryptoRandomSource.cs`; Modify: `backend/src/SimCenter.Infrastructure/DependencyInjection.cs` (`AddSingleton<IRandomSource, CryptoRandomSource>()`, `AddScoped<ITransactionRunner>(sp => sp.GetRequiredService<AppDbContext>())`)
- Modify: `backend/src/SimCenter.Infrastructure/Persistence/AppDbContext.cs` (`ITransactionRunner` 구현만. DbSet 추가 없음 — EF 모델 불변)
- Test: `backend/tests/SimCenter.Application.Tests/AgentDevices/PairingCodeFormatTests.cs`, `DeviceKeyFormatTests.cs`, `AgentPairingServiceTests.cs`, `AgentDeviceServiceTests.cs`

**Interfaces:**
- Consumes: 기존 `IApiKeyHasher.Hash(string)`, `IUnitOfWork.SaveChangesAsync`, `IIdGenerator.NewId()`, `IClock.UtcNow`, 예외 `ValidationException(field, error)`·`ForbiddenException`·`NotFoundException`.
- Produces:
  - `AgentDevice : BaseEntity { Guid UserId; string Name; string ApiKeyHash; DateTime? LastSeenAt; User? User }`
  - `AgentPairingCode : BaseEntity { Guid UserId; string CodeHash; DateTime ExpiresAt; DateTime? ConsumedAt; User? User }`
  - `IRandomSource { byte[] GetBytes(int count); }`
  - `ITransactionRunner { Task<T> RunAsync<T>(Func<CancellationToken, Task<T>> work, CancellationToken cancellationToken = default); }`
  - `IAgentDeviceRepository { Task AddAsync(AgentDevice, ct); Task<AgentDevice?> GetByIdAsync(Guid id, ct) /* tracked */; Task<AgentDevice?> GetByApiKeyHashAsync(string hash, ct); Task<IReadOnlyList<AgentDevice>> GetByUserAsync(Guid userId, ct) /* CreatedAt DESC */ }`
  - `IAgentPairingCodeRepository { Task AddAsync(AgentPairingCode, ct); Task<IReadOnlyList<AgentPairingCode>> GetUnconsumedByUserAsync(Guid userId, ct) /* tracked */; Task<bool> ExistsByHashAsync(string codeHash, ct) /* soft-delete 무시 */; Task<AgentPairingCode?> GetRedeemableByHashAsync(string codeHash, DateTime nowUtc, ct); Task<bool> TryConsumeAsync(Guid codeId, DateTime nowUtc, ct) /* 조건부 UPDATE, 1행이면 true */ }`
  - `static class PairingCodeFormat { const string Alphabet; const int Length = 8; string Create(IRandomSource); string Display(string code); string Normalize(string? input); }`
  - `static class DeviceKeyFormat { const int KeyBytes = 32; string Create(IRandomSource); }`
  - DTO(`SimCenter.Application.AgentDevices`): `PairingCodeResponse(string Code, DateTime ExpiresAt)`, `PairRequest(string? Code, string? DeviceName)`, `PairResponse(Guid DeviceId, string DeviceKey)`, `AgentDeviceDto(Guid DeviceId, string Name, DateTime? LastSeenAt, DateTime CreatedAt)`, `AgentDeviceListResponse(IReadOnlyList<AgentDeviceDto> Items)`
  - `IAgentPairingService { Task<PairingCodeResponse> IssueCodeAsync(Guid userId, ct); Task<PairResponse> PairAsync(PairRequest request, ct); }`
  - `IAgentDeviceService { Task<AgentDeviceListResponse> GetMyDevicesAsync(Guid userId, ct); Task RevokeAsync(Guid userId, Guid deviceId, ct); }`

- [ ] **Step 1: 형식 테스트 작성**

```csharp
// PairingCodeFormatTests (FixedRandom: 생성자 바이트를 그대로 돌려주는 IRandomSource)
[Fact] public void Create_MapsEachByteModulo32ToAlphabet()
{
    Assert.Equal("ABCDEFGH", PairingCodeFormat.Create(new FixedRandom(0, 1, 2, 3, 4, 5, 6, 7)));
    Assert.Equal("9A9A9A9A", PairingCodeFormat.Create(new FixedRandom(31, 32, 63, 64, 95, 96, 127, 128)));
}
[Fact] public void Display_InsertsHyphenAfterFourChars() => Assert.Equal("K7F2-9QXM", PairingCodeFormat.Display("K7F29QXM"));
[Theory] [InlineData(" k7f2-9q xm ", "K7F29QXM")] [InlineData(null, "")]
public void Normalize_UppercasesAndStripsHyphensAndWhitespace(string? input, string expected)
    => Assert.Equal(expected, PairingCodeFormat.Normalize(input));
// DeviceKeyFormatTests
[Fact] public void Create_Returns43CharBase64UrlWithoutPadding()
    => Assert.Equal(new string('_', 42) + "8", DeviceKeyFormat.Create(new FixedRandom(Enumerable.Repeat((byte)0xFF, 32).ToArray())));
```

- [ ] **Step 2: 실패 확인** — `dotnet test backend/tests/SimCenter.Application.Tests --filter "FullyQualifiedName~AgentDevices"` → 컴파일 실패(타입 없음).
- [ ] **Step 3: `IRandomSource`, `PairingCodeFormat`, `DeviceKeyFormat` 구현** — `Create`는 `random.GetBytes(Length)`의 각 바이트를 `Alphabet[b % 32]`로(256은 32의 배수라 편향 없음). 장치 키는 `System.Buffers.Text.Base64Url.EncodeToString`.
- [ ] **Step 4: 통과 확인** — 같은 명령 → PASS.
- [ ] **Step 5: 서비스 테스트 작성** (Fake: `FakeRandom`, `FakeHasher`(`"h:" + raw`), `FakeClock(Now)`, `FakeCodes`, `FakeDevices`, `FakeUnitOfWork`, `FakeTransactionRunner`(work를 바로 실행). `Now = 2026-10-17T09:00:00Z`)

```csharp
// AgentPairingServiceTests
[Fact] IssueCode_ReturnsDisplayFormattedCode_AndStoresOnlyHash
    // random → "ABCDEFGH": result.Code == "ABCD-EFGH", result.ExpiresAt == Now.AddMinutes(10),
    // 저장된 CodeHash == "h:ABCDEFGH", 저장된 어떤 필드에도 "ABCDEFGH" 원문 없음
[Fact] IssueCode_InvalidatesPreviousUnconsumedCodes          // 기존 미사용 코드 IsDeleted == true
[Fact] IssueCode_RetriesOnHashCollision_ThenSucceeds         // ExistsByHash가 2번 true → 3번째 코드 저장
[Fact] IssueCode_CollidesThreeTimes_Throws                   // Assert.ThrowsAsync<InvalidOperationException>
[Fact] Pair_ValidCode_CreatesDeviceForCodeOwner_AndReturnsKey
    // device.UserId == 코드 주인, device.ApiKeyHash == "h:" + response.DeviceKey, response.DeviceKey.Length == 43, TryConsume 호출됨
[Fact] Pair_NormalizesLowercaseHyphenAndSpaces              // " abcd-efgh " 로 성공
[Theory] [InlineData("unknown")] [InlineData("expired")] [InlineData("consumed")] [InlineData("invalidated")]
Pair_UnredeemableCode_ThrowsSameValidationError(string scenario)
    // ValidationException, Errors["code"][0] == "유효하지 않거나 만료된 코드입니다."
[Fact] Pair_AtExactExpiry_IsRejected                        // ExpiresAt == Now → 같은 ValidationException
[Fact] Pair_LostConcurrentConsume_ThrowsSameValidationError // TryConsume false → 같은 오류, 장치 생성 없음
[Theory] [InlineData(null)] [InlineData("   ")] Pair_BlankDeviceName_UsesDefault(string? name) // device.Name == "Windows PC"
[Fact] Pair_DeviceNameOver50_ThrowsValidation              // new string('가', 51) → Errors["deviceName"]
// AgentDeviceServiceTests
[Fact] GetMyDevices_ReturnsOnlyMine_NewestFirst
[Fact] Revoke_Mine_SoftDeletes                               // IsDeleted == true, UpdatedAt == Now, SaveCount == 1
[Fact] Revoke_OthersDevice_ThrowsForbidden
[Fact] Revoke_Missing_ThrowsNotFound
```

- [ ] **Step 6: 실패 확인** — 같은 필터 → 컴파일 실패.
- [ ] **Step 7: 엔티티·포트·DTO·서비스 구현** — `AgentPairingService` 상수: `CodeTtl = TimeSpan.FromMinutes(10)`, `MaxCodeGenerationAttempts = 3`, `DeviceNameMaxLength = 50`, `DefaultDeviceName = "Windows PC"`, `InvalidCodeMessage`. `PairAsync`는 `ITransactionRunner.RunAsync` 안에서 조회 → `TryConsumeAsync` → 장치 추가 → `SaveChangesAsync`. 정규화한 코드가 8자가 아니면 조회 없이 같은 오류. `CryptoRandomSource`는 `RandomNumberGenerator.GetBytes`. `AppDbContext.RunAsync`는 `Database.BeginTransactionAsync` → work → `CommitAsync`(예외 시 커밋 없이 dispose).
- [ ] **Step 8: 통과 확인** — `dotnet test backend/SimCenter.sln --nologo` → 전체 PASS(통합 테스트 포함 — EF 모델 불변).
- [ ] **Step 9: 커밋** — `feat: 장치 연결 코드·장치 키 유스케이스 추가(P6)`

---

### Task 2: 랭킹 타임존을 서버 설정으로 (D-27)

**Files:**
- Create: `backend/src/SimCenter.Application/Common/Interfaces/IRankingTimeZoneProvider.cs`
- Modify: `backend/src/SimCenter.Application/Rankings/RankingService.cs` (생성자 `RankingService(ILapRepository laps, ITrackRepository tracks, IRankingTimeZoneProvider timeZone, IClock clock)`)
- Delete: `backend/src/SimCenter.Application/Common/Interfaces/IStoreRepository.cs`, `backend/src/SimCenter.Infrastructure/Persistence/Repositories/StoreRepository.cs`
- Create: `backend/src/SimCenter.Infrastructure/Configuration/RankingOptions.cs`, `ConfiguredRankingTimeZoneProvider.cs`
- Modify: `backend/src/SimCenter.Infrastructure/DependencyInjection.cs`, `backend/src/SimCenter.Api/appsettings.json` (`"Ranking": { "TimeZoneId": "Asia/Seoul" }`)
- Test: `backend/tests/SimCenter.Application.Tests/Rankings/RankingServiceTests.cs`

**Interfaces:**
- Produces: `IRankingTimeZoneProvider { string TimeZoneId { get; } }`, `RankingOptions { const string SectionName = "Ranking"; string TimeZoneId = "Asia/Seoul"; }`

- [ ] **Step 1: 테스트 수정·추가** — `FakeStoreRepository` → `FakeTimeZoneProvider(string id)`. 기존 기대값(`"2026-07"`)은 그대로.

```csharp
[Fact] public async Task GetRanking_UsesConfiguredTimeZone()
{   // Now = 2026-07-31T16:00:00Z: 서울은 8월 1일, UTC는 7월 31일
    Assert.Equal("2026-08", (await Sut("Asia/Seoul").GetRankingAsync(_trackId, "F1_25", RankingPeriod.Monthly, null)).PeriodKey);
    Assert.Equal("2026-07", (await Sut("UTC").GetRankingAsync(_trackId, "F1_25", RankingPeriod.Monthly, null)).PeriodKey);
}
```

- [ ] **Step 2: 실패 확인** — `dotnet test backend/tests/SimCenter.Application.Tests --filter "FullyQualifiedName~RankingServiceTests"` → 컴파일 실패.
- [ ] **Step 3: 구현** — 옵션 등록은 `AddOptions<RankingOptions>().Bind(...).Validate(o => TimeZoneInfo.TryFindSystemTimeZoneById(o.TimeZoneId, out _), "Ranking:TimeZoneId가 유효한 IANA 타임존이 아닙니다.").ValidateOnStart()`. `IStoreRepository` 등록 줄 삭제(Store 엔티티·테이블은 Task 4에서 삭제).
- [ ] **Step 4: 통과 확인** — `dotnet test backend/SimCenter.sln --nologo` → PASS.
- [ ] **Step 5: 커밋** — `refactor: 랭킹 기간 타임존을 서버 설정 Ranking:TimeZoneId로 이동(D-27)`

---

### Task 3: 장치·연결 코드 영속성 + 연결 API (마이그레이션 `AddAgentDevices`)

**Files:**
- Create: `backend/src/SimCenter.Infrastructure/Persistence/Configurations/AgentDeviceConfiguration.cs`, `AgentPairingCodeConfiguration.cs`
- Create: `backend/src/SimCenter.Infrastructure/Persistence/Repositories/AgentDeviceRepository.cs`, `AgentPairingCodeRepository.cs`
- Modify: `AppDbContext.cs` (DbSet `AgentDevices`, `AgentPairingCodes`), `Infrastructure/DependencyInjection.cs` (두 저장소 Scoped), `Domain/Entities/User.cs` (`ICollection<AgentDevice> AgentDevices`)
- Create: 마이그레이션 `backend/src/SimCenter.Infrastructure/Persistence/Migrations/*_AddAgentDevices.cs`
- Modify: `backend/.config/dotnet-tools.json` (dotnet-ef 10.0.0)
- Create: `backend/src/SimCenter.Api/Common/ClaimsPrincipalExtensions.cs`, `RateLimiting/RateLimitPolicies.cs`, `Controllers/AgentPairingController.cs`, `Controllers/MyAgentDevicesController.cs`
- Modify: `backend/src/SimCenter.Api/Program.cs` (`AddRateLimiter` + `UseRateLimiter()`를 `UseAuthorization()` 다음에), `Controllers/MeController.cs` (`GetUserId` → 확장 메서드)
- Modify: `shared/openapi/openapi.yaml` (신규 4개 경로·스키마)
- Create: `backend/tests/SimCenter.Api.IntegrationTests/ApiFactory.cs`(기존 중첩 클래스 이동), `TestApi.cs`, `AgentPairingE2ETests.cs`; Modify: `TelemetryIngestE2ETests.cs` (`ApiFactory` 참조만)

**Interfaces:**
- Consumes: Task 1의 포트·서비스·DTO.
- Produces:
  - REST: `POST /api/v1/me/agent-pairing-codes` → 201 `PairingCodeResponse`; `POST /api/v1/agent/pair`(익명) → 200 `PairResponse`; `GET /api/v1/me/agent-devices` → 200 `AgentDeviceListResponse`; `DELETE /api/v1/me/agent-devices/{deviceId:guid}` → 204.
  - `static Guid ClaimsPrincipalExtensions.GetRequiredUserId(this ClaimsPrincipal user)` (실패 시 `AuthenticationException("유효하지 않은 토큰입니다.")`)
  - `RateLimitPolicies { const string AgentPair = "agent-pair"; const string PairingCodeIssue = "pairing-code-issue"; const int PermitLimit = 10; static readonly TimeSpan Window = TimeSpan.FromMinutes(1); }`
  - 테스트 헬퍼 `TestApi.RegisterAndLoginAsync(HttpClient) : Task<Guid>`(Bearer 설정), `TestApi.PairDeviceAsync(HttpClient, string deviceName) : Task<(Guid DeviceId, string DeviceKey)>`

- [ ] **Step 1: EF 도구 갱신** — `cd backend; dotnet tool update dotnet-ef --version 10.0.0; dotnet tool restore` → `dotnet ef --version`이 10.0.x.
- [ ] **Step 2: 통합 테스트 작성** (`AgentPairingE2ETests`, 실 PostgreSQL)

```csharp
[Fact] IssueCode_Pair_List_Revoke_RoundTrip
    // 발급 201, code가 ^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$ 일치
    // 익명 HttpClient로 POST /agent/pair { code, deviceName = "E2E-PC" } → 200, deviceKey.Length == 43
    // GET 목록에 name "E2E-PC", lastSeenAt null → DELETE 204 → GET 목록 비어 있음
[Fact] Pair_SameCodeTwice_SecondReturns400
[Fact] IssueCode_WithoutToken_Returns401
```

- [ ] **Step 3: 실패 확인** — `dotnet test backend/tests/SimCenter.Api.IntegrationTests --filter "FullyQualifiedName~AgentPairingE2ETests"` → 404/컴파일 실패.
- [ ] **Step 4: 영속성 구현** — 설정: `Name` 필수·50, `ApiKeyHash` 필수·64·unique, `CodeHash` 필수·64·unique, 두 엔티티 모두 `UserId` 인덱스 + `HasOne(x => x.User).WithMany(...).OnDelete(Restrict)`. `TryConsumeAsync`는 `ExecuteUpdateAsync`(조건 `Id == codeId && ConsumedAt == null && !IsDeleted && ExpiresAt > nowUtc`, `ConsumedAt = nowUtc`, `UpdatedAt = nowUtc`), `ExistsByHashAsync`는 `IgnoreQueryFilters()`.
- [ ] **Step 5: 마이그레이션 생성** — `dotnet ef migrations add AddAgentDevices --project src/SimCenter.Infrastructure --output-dir Persistence/Migrations` → `Up`이 `agent_devices`, `agent_pairing_codes` 생성만 포함하는지 확인(다른 테이블 변경 없음).
- [ ] **Step 6: API 구현** — 컨트롤러는 서비스만 호출. `AgentPairingController`: `[Route("api/v1/agent")] [AllowAnonymous] [EnableRateLimiting(RateLimitPolicies.AgentPair)]`. `MyAgentDevicesController`: `[Route("api/v1/me")] [Authorize]`, 발급 액션에 `[EnableRateLimiting(RateLimitPolicies.PairingCodeIssue)]`. 리미터: IP 파티션(`RemoteIpAddress`), 사용자 파티션(`sub` 클레임), 둘 다 FixedWindow, `RejectionStatusCode = 429`.
- [ ] **Step 7: 통과 확인** — `dotnet test backend/SimCenter.sln --nologo` → 전체 PASS.
- [ ] **Step 8: 커밋** — `feat: 장치 연결 API와 AgentDevice 영속성 추가(마이그레이션 AddAgentDevices)`

---

### Task 4: 인입 귀속 전환 + 카페 모델 제거 (마이그레이션 `PersonalMode`, D-25)

**Files:**
- Modify: `Domain/Entities/Lap.cs` (`DrivingSessionId`·`DrivingSession` 제거, `Guid AgentDeviceId`·`AgentDevice? AgentDevice` 추가), `Domain/Entities/User.cs` (`Sessions` 제거)
- Delete: `Domain/Entities/Store.cs`, `SimRig.cs`, `DrivingSession.cs`, `Domain/Enums/SessionStatus.cs`, `Application/Sessions/`(전체), `Application/Common/Interfaces/ISimRigRepository.cs`, `IDrivingSessionRepository.cs`, `Infrastructure/Persistence/Configurations/StoreConfiguration.cs`, `SimRigConfiguration.cs`, `DrivingSessionConfiguration.cs`, `Infrastructure/Persistence/Repositories/SimRigRepository.cs`, `DrivingSessionRepository.cs`, `Api/Controllers/SessionsController.cs`, `backend/tests/SimCenter.Application.Tests/Sessions/`
- Modify: `Application/Telemetry/TelemetryContracts.cs` (`TelemetryEnvelopeDto`에서 `RigCode` 제거), `ITelemetryIngestService.cs`, `TelemetryIngestService.cs`, `Application/DependencyInjection.cs`
- Modify: `Infrastructure/Persistence/Configurations/LapConfiguration.cs` (`AgentDevice` FK Restrict, `UserId` → users FK Restrict), `AppDbContext.cs` (Stores·SimRigs·DrivingSessions DbSet 제거), `Infrastructure/DependencyInjection.cs`, `Identity/AgentApiKeyAuthenticationHandler.cs`, `Persistence/Seed/DbSeeder.cs` (매장·좌석·개발 키 제거, 트랙 시드 유지)
- Create: 마이그레이션 `*_PersonalMode.cs`
- Modify: `Api/Hubs/TelemetryHub.cs`
- Modify: `backend/tests/SimCenter.Application.Tests/Telemetry/TelemetryIngestServiceTests.cs`, `backend/tests/SimCenter.Domain.Tests/EntityDefaultsTests.cs`, `backend/tests/SimCenter.Api.IntegrationTests/TelemetryIngestE2ETests.cs`
- Modify: `shared/schema/telemetry_envelope.json`, `shared/samples/telemetry_lap_finished_envelope.json` (`rigCode` 제거), `shared/openapi/openapi.yaml` (제목, `/sessions/*` 경로·`CheckInRequest`·`DrivingSession` 스키마 제거)
- Modify: `CLAUDE.md` (스펙 §11 항목), `docs/08-open-decisions.md` (D-25~27 추가, 대체된 결정에 "→ D-25로 대체" 표기, 요약표 갱신)

**Interfaces:**
- Consumes: Task 1 `IAgentDeviceRepository`, Task 3 영속성.
- Produces:
  - `ITelemetryIngestService.IngestAsync(TelemetryEnvelopeDto envelope, Guid authenticatedDeviceId, CancellationToken cancellationToken = default) : Task<IngestResult>`
  - `TelemetryEnvelopeDto(Guid EventId, string GameCode, DateTime OccurredAt, string Type, JsonElement Payload)`
  - `AgentApiKeyDefaults.DeviceIdClaim = "deviceId"` (`RigCodeClaim` 삭제). 인증 성공 시 클레임 `deviceId`·`sub`(UserId).
  - `TelemetryIngestService` 상수 `LastSeenWriteInterval = TimeSpan.FromMinutes(1)`, `RevokedDeviceReason = "연결이 해제된 장치입니다."`

- [ ] **Step 1: 단위 테스트 갱신** — Fake `FakeSimRigRepository`·`FakeDrivingSessionRepository` → `FakeAgentDeviceRepository`(삭제된 장치는 `GetByIdAsync`에서 null — 전역 필터 모사). 삭제: "활성 세션 없음 → Drop", "알 수 없는 좌석 Reject". 추가:

```csharp
[Fact] LapFinished_FromDevice_AttributesToDeviceOwner      // lap.UserId == _ownerId, lap.AgentDeviceId == _deviceId, SaveCount == 1
[Theory] [InlineData("missing")] [InlineData("revoked")]
AnyEvent_FromMissingOrRevokedDevice_Rejects(string scenario) // Acknowledged false, RejectReason == "연결이 해제된 장치입니다.", 랩 없음
[Fact] LastSeenAt_WrittenWhenNull_SkippedWithinOneMinute_WrittenAfter
    // LastSeenAt null → Now로 기록 / Now-30s → 그대로 / Now-61s → Now로 기록
[Fact] NonLapEvent_UpdatesLastSeenAt_WithSingleSave          // "SessionStarted" → Ack, SaveCount == 1, 랩 없음
[Fact] DuplicateEvent_IsAckedBeforeDeviceCheck               // ProcessedEvent 있으면 장치가 없어도 Ack
```
  `EntityDefaultsTests`: DrivingSession 기본값 테스트 삭제, `AgentDevice_DefaultsToNeverSeenAndActive`(LastSeenAt null, IsDeleted false) 추가.

- [ ] **Step 2: E2E 갱신** — `TelemetryIngestE2ETests.LapFinished_FromPairedDevice_IsAttributedAndPersisted`: `TestApi.RegisterAndLoginAsync` → `PairDeviceAsync` → 장치 키로 허브 연결 → envelope(`rigCode` 없음) 전송 → DB `lap.UserId == userId && lap.AgentDeviceId == deviceId` → `/me/laps` PB 83452 → `/rankings?...&date=2026-07-07` periodKey `"2026-07"` → `DELETE /me/agent-devices/{id}` → 같은 연결로 새 eventId 전송 → `RejectReason == "연결이 해제된 장치입니다."`. `ResetRigAsync` 삭제.
- [ ] **Step 3: 실패 확인** — `dotnet test backend/SimCenter.sln --nologo` → 컴파일 실패.
- [ ] **Step 4: 도메인·애플리케이션·인프라·API 전환 구현** — 인입 순서는 스펙 §5 그대로(멱등 → 장치 확인 → LastSeenAt → 유형 → 파싱 → 트랙 → 적격 → PB → 저장 → 브로드캐스트). LastSeenAt 변경은 LapFinished면 랩 저장과 같은 `SaveChangesAsync`에 포함하고, 그 밖의 반환 경로는 변경이 있을 때만 1회 저장. 허브는 `deviceId` 클레임을 `Guid.TryParse`, 실패 시 `Reject("인증된 장치 정보가 없습니다.")`. 로그의 `rig=`는 `device=`로.
- [ ] **Step 5: 마이그레이션 생성·수정** — `dotnet ef migrations add PersonalMode --project src/SimCenter.Infrastructure --output-dir Persistence/Migrations`. 생성된 `Up` 맨 앞에 `migrationBuilder.Sql("DELETE FROM lap_sectors; DELETE FROM laps; DELETE FROM processed_events;");`를 넣는다(기존 행이 있으면 NOT NULL FK 추가가 실패). 이어서 `driving_session_id` 제거 → `agent_device_id` 추가·FK → `user_id` FK → `driving_sessions`·`sim_rigs`·`stores` 삭제 순서인지 확인. `Down`은 생성본 유지(데이터는 복원하지 않는다고 주석).
- [ ] **Step 6: 계약·헌장·결정 문서 갱신** — 파일 목록의 shared/, CLAUDE.md, docs/08.
- [ ] **Step 7: 통과 확인** — `dotnet test backend/SimCenter.sln --nologo` → 전체 PASS. 이어서 백엔드를 한 번 실행해 로컬 DB에 `PersonalMode`가 적용되고 시작 로그에 오류가 없는지 확인 후 종료.
- [ ] **Step 8: 커밋** — `feat!: 개인 모드 전환 — 랩을 연결된 장치 주인에게 귀속, 매장·좌석·체크인 제거(D-25, 마이그레이션 PersonalMode)`

---

### Task 5: 내 트랙 요약 + 랩 정렬 API

**Files:**
- Create: `backend/src/SimCenter.Application/Rankings/MyLapsSort.cs`, `MyTrackSummaryRow.cs`
- Modify: `Application/Rankings/RankingDtos.cs`, `IRankingService.cs`, `RankingService.cs`, `Application/Common/Interfaces/ILapRepository.cs`, `Infrastructure/Persistence/Repositories/LapRepository.cs`, `Api/Controllers/MeController.cs`, `shared/openapi/openapi.yaml`
- Test: `backend/tests/SimCenter.Application.Tests/Rankings/RankingServiceTests.cs`, `backend/tests/SimCenter.Api.IntegrationTests/TelemetryIngestE2ETests.cs`(시나리오 추가)

**Interfaces:**
- Produces:
  - `enum MyLapsSort { Recent, Fastest }`
  - `record MyTrackSummaryRow(Guid TrackId, string TrackName, string GameCode, int LapCount, int? BestValidLapTimeMs, DateTime LastSetAt)`
  - `record MyTrackDto(Guid TrackId, string TrackName, string GameCode, int LapCount, int? BestValidLapTimeMs, DateTime LastSetAt)`, `record MyTracksResponse(IReadOnlyList<MyTrackDto> Items)`
  - `ILapRepository.GetMyLapsAsync(Guid userId, Guid? trackId, SessionType? sessionType, MyLapsSort sort, int skip, int take, ct)`, `ILapRepository.GetMyTrackSummariesAsync(Guid userId, ct) : Task<IReadOnlyList<MyTrackSummaryRow>>`
  - `IRankingService.GetMyLapsAsync(Guid userId, Guid? trackId, SessionType? sessionType, MyLapsSort sort, int page, int pageSize, ct)`, `IRankingService.GetMyTracksAsync(Guid userId, ct) : Task<MyTracksResponse>`
  - REST: `GET /api/v1/me/laps?sort=recent|fastest`(기본 recent), `GET /api/v1/me/tracks`

- [ ] **Step 1: 테스트 작성**

```csharp
[Fact] GetMyLaps_PassesSortToRepository                     // Fastest 전달 → FakeLapRepository.LastSort == Fastest
[Fact] GetMyTracks_MapsRowsInRepositoryOrder                // 행 2개 → DTO 2개, 필드 일치, 순서 유지
[Fact] GetMyTracks_NoLaps_ReturnsEmpty                      // Items.Count == 0
// E2E 시나리오 MyLaps_SortAndTrackSummary
//   같은 트랙에 (85000 유효, t1) (80000 무효, t2) (83000 유효, t3) 전송
//   sort=fastest → [83000, 85000, 80000] / sort=recent → [83000, 80000, 85000]
//   /me/tracks → lapCount 3, bestValidLapTimeMs 83000, lastSetAt == t3
```

- [ ] **Step 2: 실패 확인** — `dotnet test backend/SimCenter.sln --nologo` → 컴파일 실패.
- [ ] **Step 3: 구현** — 정렬: Fastest = `OrderByDescending(IsValid).ThenBy(LapTimeMs).ThenBy(SetAt)`, Recent = `OrderByDescending(SetAt)`. 요약: 사용자 랩을 `TrackId`로 묶어 개수, 유효 랩 최소 랩타임(없으면 null), 최대 `SetAt`, 트랙 이름 조인, `LastSetAt` 내림차순. 컨트롤러 `[FromQuery] MyLapsSort sort = MyLapsSort.Recent`(쿼리 `fastest` 대소문자 무시 바인딩).
- [ ] **Step 4: 통과 확인** — 같은 명령 → PASS.
- [ ] **Step 5: 커밋** — `feat: 내 트랙 요약(/me/tracks)과 랩 정렬(sort=recent|fastest) 추가`

---

### Task 6: Agent 장치 키 저장소 (DPAPI)

**Files:**
- Modify: `agent/src/SimCenter.Agent.Infrastructure/SimCenter.Agent.Infrastructure.csproj` (`<PackageReference Include="System.Security.Cryptography.ProtectedData" Version="10.0.0" />`)
- Create: `agent/src/SimCenter.Agent.Infrastructure/Credentials/IDeviceCredentialStore.cs`, `DpapiDeviceCredentialStore.cs`
- Modify: `agent/src/SimCenter.Agent.Infrastructure/DependencyInjection.cs` (`AddSingleton<IDeviceCredentialStore>(sp => new DpapiDeviceCredentialStore(DpapiDeviceCredentialStore.DefaultPath, logger))`)
- Test: `agent/tests/SimCenter.Agent.Infrastructure.Tests/DpapiDeviceCredentialStoreTests.cs`

**Interfaces:**
- Produces: `IDeviceCredentialStore { string? Load(); void Save(string deviceKey); void Clear(); event EventHandler? Changed; }`, `DpapiDeviceCredentialStore(string filePath, ILogger<DpapiDeviceCredentialStore> logger)`, `static string DefaultPath` (`%LOCALAPPDATA%\SimCenter\Agent\device.key`)

- [ ] **Step 1: 테스트 작성** (테스트마다 임시 폴더 경로 사용, 끝나면 삭제)

```csharp
[Fact] SaveThenLoad_RoundTrips                    // Save("key-123") → Load() == "key-123"
[Fact] Load_MissingFile_ReturnsNull
[Fact] Load_CorruptFile_ReturnsNull               // 파일에 임의 바이트 → null (예외 없음)
[Fact] Save_OverwritesExistingKey                 // Save("a"); Save("b") → Load() == "b"
[Fact] Save_FileDoesNotContainPlaintext           // 파일 바이트를 UTF8로 읽은 문자열에 "key-123" 없음
[Fact] SaveAndClear_RaiseChanged                  // 두 번 모두 Changed 발생, Clear 후 Load() == null
```

- [ ] **Step 2: 실패 확인** — `dotnet test agent/tests/SimCenter.Agent.Infrastructure.Tests --filter "FullyQualifiedName~DpapiDeviceCredentialStoreTests"` → 컴파일 실패.
- [ ] **Step 3: 구현** — `ProtectedData.Protect(UTF8(key), entropy: 고정 앱 엔트로피 바이트, DataProtectionScope.CurrentUser)`. 쓰기는 같은 폴더의 임시 파일에 쓴 뒤 `File.Move(temp, path, overwrite: true)`. 복호화·IO 실패는 `LogError`(키 내용 없이) 후 null. 클래스에 `[SupportedOSPlatform("windows")]`.
- [ ] **Step 4: 통과 확인** — 같은 명령 → PASS.
- [ ] **Step 5: 커밋** — `feat(agent): DPAPI 장치 키 저장소 추가`

---

### Task 7: Agent 설정·봉투 정리 + 키 기반 업로드 + 401 처리

**Files:**
- Modify: `agent/src/SimCenter.Agent.Core/Telemetry/Events/TelemetryEnvelope.cs` (`RigCode` 제거), `AgentIdentity.cs` (`AgentIdentity(string GameCode)`), `Core/Analysis/DomainEventFactory.cs`
- Modify: `agent/src/SimCenter.Agent.Infrastructure/Configuration/AgentOptions.cs` (`RigCode`·`AgentCredential`·`BackendUrl` 제거, `ServerBaseUrl` 추가 — 비면 업로드 비활성)
- Create: `Infrastructure/Configuration/AgentEndpoints.cs`, `Infrastructure/Upload/ITelemetryHubSession.cs`, `SignalRTelemetryHubSessionFactory.cs`, `UploadState.cs`, `UploadStatusTracker.cs`, `UnauthorizedDetector.cs`
- Modify: `Infrastructure/Upload/TelemetryUploadService.cs`, `Sinks/OutboxTelemetrySink.cs` (wire `rigCode` 제거), `Sinks/LoggingTelemetrySink.cs`, `DependencyInjection.cs`
- Modify: `agent/src/SimCenter.Agent.Cli/appsettings.json`, `agent/src/SimCenter.Agent.Tray/appsettings.json` (`"ServerBaseUrl": "http://localhost:5284"`, 옛 키 삭제)
- Test: `agent/tests/SimCenter.Agent.Core.Tests/DomainEventFactoryTests.cs`, `agent/tests/SimCenter.Agent.Infrastructure.Tests/TelemetryOutboxTests.cs`, `AgentEndpointsTests.cs`, `UnauthorizedDetectorTests.cs`, `TelemetryUploadServiceTests.cs`

**Interfaces:**
- Consumes: Task 6 `IDeviceCredentialStore`.
- Produces:
  - `static class AgentEndpoints { Uri PairUri(string serverBaseUrl); Uri TelemetryHubUri(string serverBaseUrl); }` (끝 `/` 유무 무관)
  - `enum UploadState { Disabled, Unpaired, Connecting, Connected, Unauthorized }`, `sealed class UploadStatusTracker { UploadState State { get; } event EventHandler? StateChanged; void Set(UploadState state); }`
  - `interface ITelemetryHubSession : IAsyncDisposable { bool IsConnected { get; } Task StartAsync(CancellationToken ct); Task<SubmitResult> SubmitAsync(JsonElement envelope, CancellationToken ct); }`, `record SubmitResult(bool Acknowledged, string? RejectReason)`, `interface ITelemetryHubSessionFactory { ITelemetryHubSession Create(Uri hubUri, string deviceKey); }`
  - `static class UnauthorizedDetector { bool IsUnauthorized(Exception ex); }`
  - `TelemetryUploadService(IOptions<AgentOptions>, TelemetryOutbox, IDeviceCredentialStore, ITelemetryHubSessionFactory, UploadStatusTracker, ILogger<TelemetryUploadService>)`

- [ ] **Step 1: 테스트 작성·수정**

```csharp
// DomainEventFactoryTests: new AgentIdentity("F1_25"), envelope에 RigCode 없음(기존 Assert 삭제)
// TelemetryOutboxTests: Assert.False(root.TryGetProperty("rigCode", out _))
[Theory] [InlineData("http://localhost:5284")] [InlineData("http://localhost:5284/")]
AgentEndpoints_BuildPairAndHubUris(string baseUrl)   // ".../api/v1/agent/pair", ".../hubs/telemetry"
[Fact] UnauthorizedDetector_True_ForHttp401_IncludingInner     // HttpRequestException(StatusCode 401), 그것을 inner로 가진 예외
[Fact] UnauthorizedDetector_False_ForOtherErrors               // 500, SocketException
// TelemetryUploadServiceTests — FakeSessionFactory·FakeSession, 실제 TelemetryOutbox(임시 SQLite), 메모리 FakeCredentialStore
[Fact] EmptyServerBaseUrl_StaysDisabled_NeverConnects          // State == Disabled
[Fact] NoKey_StaysUnpaired_ThenConnectsAfterKeySaved           // Unpaired → Save("k") → Factory.Create(hubUri, "k") 호출 → Connected
[Fact] Ack_RemovesOutboxItem
[Fact] Unauthorized_StopsUploading_AndKeepsOutboxItems
    // StartAsync가 HttpRequestException(401) → State == Unauthorized, Outbox 항목 그대로, 추가 Create 호출 없음
    // 이후 다른 키 Save → 재시도해 Connected, 항목 전송·삭제
```

- [ ] **Step 2: 실패 확인** — `dotnet test agent/SimCenter.Agent.sln --nologo` → 컴파일 실패.
- [ ] **Step 3: 구현** — 업로드 루프: `ServerBaseUrl`이 비면 `Disabled`로 끝. 키가 없거나 `Unauthorized` 상태면 `Changed`(새 키)까지 대기하고, 키가 없을 때 한 번 경고 `"계정 미연결 — pair <코드>로 연결하세요"`. 키가 있으면 `Factory.Create(TelemetryHubUri, key)` → `StartAsync` → 배수(응답이 오면 Ack·Reject 모두 삭제, 기존 규칙). 예외가 `UnauthorizedDetector.IsUnauthorized`면 세션을 버리고 `Unauthorized`로 전환(Outbox 미변경), 아니면 기존 지수 백오프(최대 30초). `SignalRTelemetryHubSessionFactory`는 기존 `BuildConnection` 설정(헤더 `X-Agent-Key`, camelCase, enum 문자열, 자동 재접속)을 옮긴다.
- [ ] **Step 4: 통과 확인** — 같은 명령 → PASS.
- [ ] **Step 5: 커밋** — `feat(agent): 장치 키 기반 업로드와 401 중단 처리, 봉투 rigCode 제거`

---

### Task 8: Agent 연결 클라이언트 + Cli `pair` 명령

**Files:**
- Create: `agent/src/SimCenter.Agent.Infrastructure/Pairing/IAgentPairingClient.cs`, `AgentPairingClient.cs`, `PairOutcome.cs`, `PairCommand.cs`
- Modify: `Infrastructure/DependencyInjection.cs` (`AddHttpClient<IAgentPairingClient, AgentPairingClient>()`), `agent/src/SimCenter.Agent.Cli/Program.cs`
- Test: `agent/tests/SimCenter.Agent.Infrastructure.Tests/AgentPairingClientTests.cs`, `PairCommandTests.cs`

**Interfaces:**
- Consumes: Task 6 `IDeviceCredentialStore`, Task 7 `AgentEndpoints.PairUri`, `AgentOptions.ServerBaseUrl`.
- Produces:
  - `record PairOutcome(bool Succeeded, string Message)`
  - `interface IAgentPairingClient { Task<PairOutcome> PairAsync(string code, string deviceName, CancellationToken ct); }` — 성공 시 키를 저장한다.
  - `static class PairCommand { Task<int> RunAsync(IReadOnlyList<string> args, IAgentPairingClient client, string deviceName, TextWriter output, CancellationToken ct); }` — `["pair", code]`만 처리, 반환 0/1.

- [ ] **Step 1: 테스트 작성** (Fake `HttpMessageHandler`, 메모리 credential store)

```csharp
[Fact] Pair_200_SavesKeyAndSucceeds        // 요청 본문 { code, deviceName }, 경로 /api/v1/agent/pair, store.Load() == 응답 deviceKey
[Fact] Pair_400_DoesNotSave_ReturnsInvalidCodeMessage  // Message == "유효하지 않거나 만료된 코드입니다."
[Fact] Pair_429_ReturnsTooManyRequestsMessage          // Message == "요청이 너무 많습니다. 잠시 후 다시 시도하세요."
[Fact] Pair_NetworkError_ReturnsUnreachableMessage     // Message가 "서버에 연결할 수 없습니다"로 시작, 저장 없음
[Fact] PairCommand_WithCode_Success_Returns0           // 출력에 "연결되었습니다" 포함, 코드 원문은 출력하지 않음
[Fact] PairCommand_MissingCode_PrintsUsage_Returns1    // "사용법: SimCenter.Agent.Cli pair <코드>"
[Fact] PairCommand_Failure_Returns1
```

- [ ] **Step 2: 실패 확인** — `dotnet test agent/tests/SimCenter.Agent.Infrastructure.Tests --filter "FullyQualifiedName~Pair"` → 컴파일 실패.
- [ ] **Step 3: 구현** — `Program.cs`는 `args`가 `pair`로 시작하면 호스트를 띄우지 않고 서비스 공급자에서 클라이언트를 꺼내 `PairCommand.RunAsync(args, client, Environment.MachineName, Console.Out, ct)`의 결과로 종료한다. 그 외에는 기존 호스트 실행.
- [ ] **Step 4: 통과 확인** — 같은 명령 → PASS. 수동: 백엔드를 띄우고 Swagger로 코드 발급 → `cd agent/src/SimCenter.Agent.Cli; dotnet run -- pair <코드>` → "연결되었습니다" → `dotnet run` 로그에 `TelemetryHub 연결됨`.
- [ ] **Step 5: 커밋** — `feat(agent): 연결 코드로 계정에 연결하는 pair 명령 추가`

---

### Task 9: Tray 계정 연결 UI

**Files:**
- Modify: `agent/src/SimCenter.Agent.Tray/MainWindow.xaml` ("계정 연결" 영역: 상태 텍스트 `AccountStatusText`, 코드 입력 `PairingCodeBox`, `[연결]` `PairButton`, `[이 PC 연결 끊기]` `UnlinkButton`, 오류 `AccountErrorText`)
- Modify: `agent/src/SimCenter.Agent.Tray/MainWindow.xaml.cs` (생성자에 `IAgentPairingClient`, `IDeviceCredentialStore`, `UploadStatusTracker` 추가), `App.xaml.cs` (서비스 전달)

**Interfaces:**
- Consumes: Task 6·7·8의 `IDeviceCredentialStore`, `UploadStatusTracker`, `IAgentPairingClient`.

- [ ] **Step 1: 구현** — 상태 문구: `Unpaired` → `"미연결"`, `Connecting`·`Connected` → `"연결됨 · {Environment.MachineName}"`, `Unauthorized` → `"다시 연결 필요"`, `Disabled` → `"업로드 꺼짐(ServerBaseUrl 비어 있음)"`. `StateChanged`는 Dispatcher로 UI 갱신. [연결]은 비동기로 `PairAsync`(진행 중 버튼 비활성), 실패 메시지는 `AccountErrorText`. [이 PC 연결 끊기]는 `Clear()`.
- [ ] **Step 2: 빌드 확인** — `dotnet build agent/SimCenter.Agent.sln --nologo` → 경고·오류 0.
- [ ] **Step 3: 수동 확인** — Tray 실행 → "미연결" → Swagger(또는 웹)에서 코드 발급 후 입력 → "연결됨 · {PC 이름}" → 장치 해제 후 Tray 재시작 → "다시 연결 필요" → 새 코드로 재연결 → "연결됨".
- [ ] **Step 4: 커밋** — `feat(agent): Tray에 계정 연결 UI 추가`

---

### Task 10: Flutter 테마 + 반응형 셸 + Dashboard + Leaderboard

**Files:**
- Create: `app/lib/core/theme/app_colors.dart`; Modify: `app/lib/core/theme/app_theme.dart` (토큰 사용)
- Create: `app/lib/core/shell/app_shell.dart`, `app/lib/core/shell/nav_items.dart`
- Modify: `app/lib/core/router/app_router.dart` (`ShellRoute`; 로그인 상태에서 인증 화면이면 `/`로; `/home`→`/` 리다이렉트)
- Create: `app/lib/features/dashboard/presentation/dashboard_page.dart`, `app/lib/features/ranking/presentation/leaderboard_page.dart`
- Modify: `app/lib/features/ranking/application/ranking_providers.dart`, `app/lib/features/laps/presentation/my_laps_page.dart`(셸 안 `/laps`로 임시 사용 — Task 11에서 교체)
- Delete: `app/lib/features/session/`(전체), `app/lib/features/ranking/presentation/home_page.dart`, `today_ranking_page.dart`
- Test: `app/test/app_shell_test.dart`, `app/test/ranking_query_test.dart`

**Interfaces:**
- Produces:
  - `AppColors` 상수: `background 0xFF12141C`, `surface 0xFF181B25`, `border 0xFF262A36`, `accent 0xFF6366F1`, `textPrimary 0xFFE5E7EB`, `textMuted 0xFF9CA3AF`
  - `const double kSidebarBreakpoint = 900;`, `const double kSidebarWidth = 220;`, `class AppShell extends ConsumerWidget { const AppShell({required Widget child, required String location}); }`
  - `class NavItem { final String label; final IconData icon; final String path; }`, `List<NavItem> navItems` — 이 태스크에서는 Dashboard(`/`) · Laps(`/laps`) · Leaderboard(`/leaderboard`)
  - `class RankingQuery { final String trackId; final String period; }`(값 동등성), `bool shouldApplyHubSnapshot(RankingQuery query, Map<String, dynamic> payload)`, `rankingControllerProvider` family 키 → `RankingQuery`
  - 경로: `/` DashboardPage, `/leaderboard?trackId=` LeaderboardPage

- [ ] **Step 1: 테스트 작성**

```dart
testWidgets('900px 이상이면 사이드바와 메뉴 라벨이 보인다', (t) async { /* 1000x800 → find.text('Dashboard'), 메뉴 열기 버튼 없음 */ });
testWidgets('900px 미만이면 서랍 메뉴 버튼이 보인다', (t) async { /* 600x800 → find.byTooltip('메뉴 열기') */ });
test('shouldApplyHubSnapshot_OnlyForMonthlyOfSameTrack', () {
  const q = RankingQuery(trackId: 't1', period: 'monthly');
  expect(shouldApplyHubSnapshot(q, {'trackId': 't1'}), isTrue);
  expect(shouldApplyHubSnapshot(q, {'trackId': 't2'}), isFalse);
  expect(shouldApplyHubSnapshot(const RankingQuery(trackId: 't1', period: 'daily'), {'trackId': 't1'}), isFalse);
});
```

- [ ] **Step 2: 실패 확인** — `cd app; flutter test` → 컴파일 실패.
- [ ] **Step 3: 구현** — Dashboard: `"Welcome {displayName}!"`, 최근 랩 5개(`getMyLaps(pageSize: 5)`), 랩이 없으면 안내 문구. Leaderboard: 트랙 드롭다운(`tracksProvider`), 기간 `SegmentedButton`(일·월·연 → `daily`·`monthly`·`yearly`, 기본 monthly), TOP10. 컨트롤러는 허브 `rankingUpdated`가 오면 `shouldApplyHubSnapshot`이 참일 때 그대로 반영하고, 같은 트랙의 다른 기간이면 REST로 다시 읽는다. 사이드바 하단에 `displayName`과 로그아웃.
- [ ] **Step 4: 통과 확인** — `flutter analyze` 이슈 0, `flutter test` PASS. 수동: `flutter run -d web-server --web-hostname localhost --web-port 5960 --dart-define=API_BASE_URL=http://localhost:5284`로 1000px·600px 폭에서 확인.
- [ ] **Step 5: 커밋** — `feat(app): 사이드바 셸·새 테마·Dashboard·Leaderboard 추가, 체크인 화면 제거`

---

### Task 11: Flutter Laps (트랙 목록 + 트랙별 랩 표)

**Files:**
- Modify: `app/lib/features/laps/domain/lap_models.dart` (`MyTrack`), `data/laps_repository.dart` (`getMyLaps(... sort)`, `getMyTracks()`), `application/laps_providers.dart`
- Create: `app/lib/features/laps/presentation/laps_page.dart`, `track_laps_page.dart`, `app/lib/core/util/pagination.dart`
- Delete: `app/lib/features/laps/presentation/my_laps_page.dart`
- Modify: `app/lib/core/router/app_router.dart` (`/laps`, `/laps/tracks/:trackId`), `features/dashboard/presentation/dashboard_page.dart` ("View all lap times" → `/laps`)
- Test: `app/test/models_test.dart`, `app/test/pagination_test.dart`, `app/test/laps_page_test.dart`

**Interfaces:**
- Consumes: Task 5 `GET /me/tracks`, `GET /me/laps?sort`.
- Produces:
  - `class MyTrack { trackId, trackName, gameCode, int lapCount, int? bestValidLapTimeMs, DateTime lastSetAt; factory MyTrack.fromJson }`
  - `LapsRepository.getMyLaps({String? trackId, String? sessionType, String sort = 'recent', int page = 1, int pageSize = 20})`, `LapsRepository.getMyTracks() : Future<List<MyTrack>>`
  - `myTracksProvider`, `class TrackLapsQuery { trackId, sort, page }`, `trackLapsProvider` (family `TrackLapsQuery`), `const int kTrackLapsPageSize = 15;`
  - `String paginationLabel({required int page, required int pageSize, required int total})`

- [ ] **Step 1: 테스트 작성**

```dart
test('MyTrack.fromJson', () { /* bestValidLapTimeMs null 허용, lastSetAt 파싱 */ });
test('paginationLabel', () {
  expect(paginationLabel(page: 1, pageSize: 15, total: 76), 'Showing 1 to 15 of 76');
  expect(paginationLabel(page: 6, pageSize: 15, total: 76), 'Showing 76 to 76 of 76');
  expect(paginationLabel(page: 1, pageSize: 15, total: 0), 'Showing 0 of 0');
});
testWidgets('LapsPage_Empty_ShowsGuide', (t) async { /* myTracksProvider override → [] → find.text('아직 기록된 랩이 없습니다') */ });
```

- [ ] **Step 2: 실패 확인** — `flutter test` → 컴파일 실패.
- [ ] **Step 3: 구현** — `LapsPage`: 트랙명 · 최고 유효 랩(`formatLapTime`, null이면 `-`) · 랩 수 · 마지막 주행일, 행을 누르면 `/laps/tracks/:trackId`. `TrackLapsPage`: Recent/Fastest `SegmentedButton`, 표(랩타임 + 유효 ✓, S1·S2·S3, 세션 유형, 날짜), 하단 `paginationLabel` + 이전/다음.
- [ ] **Step 4: 통과 확인** — `flutter analyze` 0, `flutter test` PASS.
- [ ] **Step 5: 커밋** — `feat(app): Laps 화면(트랙 목록·트랙별 랩 표) 추가`

---

### Task 12: Flutter Telemetry App + 연결 상태

**Files:**
- Create: `app/lib/core/time/clock_provider.dart`, `app/lib/core/util/relative_time.dart`
- Create: `app/lib/features/devices/domain/device_models.dart`, `domain/connection_status.dart`, `data/devices_repository.dart`, `application/devices_providers.dart`, `presentation/telemetry_app_page.dart`, `presentation/connection_status_card.dart`
- Modify: `app/lib/core/shell/nav_items.dart` (Telemetry App `/telemetry-app` 추가), `app/lib/core/router/app_router.dart`, `features/dashboard/presentation/dashboard_page.dart` (연결 상태 카드)
- Test: `app/test/relative_time_test.dart`, `app/test/connection_status_test.dart`, `app/test/models_test.dart`, `app/test/telemetry_app_page_test.dart`

**Interfaces:**
- Consumes: Task 3 연결·장치 API.
- Produces:
  - `final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);`
  - `String formatRemaining(Duration remaining)` (`m:ss`, 0 이하 `'만료됨'`), `String describeAgo(Duration elapsed)` (`'N분 전'`/`'N시간 전'`/`'N일 전'`)
  - `class AgentDevice { deviceId, name, DateTime? lastSeenAt, DateTime createdAt; fromJson }`, `class PairingCode { code, DateTime expiresAt; fromJson }`
  - `enum ConnectionKind { noDevices, neverReceived, receiving, stale }`, `const Duration kReceivingWindow = Duration(minutes: 5);`, `ConnectionKind connectionKindOf(List<AgentDevice> devices, DateTime now)`, `String connectionStatusText(List<AgentDevice> devices, DateTime now)`
  - `DevicesRepository.issuePairingCode() : Future<PairingCode>`, `getDevices() : Future<List<AgentDevice>>`, `revoke(String deviceId) : Future<void>`
  - `agentDevicesProvider` (`FutureProvider<List<AgentDevice>>`), `class PairingCodeController extends AsyncNotifier<PairingCode?> { Future<void> issue(); }`

- [ ] **Step 1: 테스트 작성**

```dart
test('formatRemaining_ZeroOrNegative_IsExpired', () {
  expect(formatRemaining(const Duration(minutes: 9, seconds: 59)), '9:59');
  expect(formatRemaining(Duration.zero), '만료됨');
  expect(formatRemaining(const Duration(seconds: -3)), '만료됨');
});
test('describeAgo', () { /* 5분 → '5분 전', 3시간 → '3시간 전', 82일 → '82일 전' */ });
test('connectionStatusText', () {
  // 장치 없음 → '연결된 PC가 없습니다'
  // lastSeenAt 모두 null → '아직 받은 데이터가 없습니다'
  // 가장 최근 lastSeenAt이 now-4분 → '데이터 수신 중'
  // 가장 최근 lastSeenAt이 now-82일 → '최근 데이터 없음 · 마지막 수신 82일 전'
});
testWidgets('TelemetryAppPage_NoDevices_ShowsGuide', (t) async { /* agentDevicesProvider override → [] → '연결된 PC가 없습니다', '연결 코드 발급' 버튼 */ });
```

- [ ] **Step 2: 실패 확인** — `flutter test` → 컴파일 실패.
- [ ] **Step 3: 구현** — 페이지 순서는 스펙 §7.3: ① 다운로드 "설치 파일 준비 중" + 개발용 실행 안내 `dotnet run -- pair <코드>` ② 코드 발급·남은 시간(1초 `Timer`, `clockProvider` 사용)·복사(`Clipboard.setData`), 만료되면 "만료됨" + [다시 발급] ③ F1 25 UDP 설정 표(On · 2025 · 20777 · Agent PC IP) ④ 연결된 PC 목록 + [연결 해제](확인 대화상자 후 `revoke`, 목록 갱신) ⑤ Connection Status. Dashboard 상단에 `ConnectionStatusCard`(장치가 없으면 Telemetry App으로 이동 버튼).
- [ ] **Step 4: 통과 확인** — `flutter analyze` 0, `flutter test` PASS.
- [ ] **Step 5: 커밋** — `feat(app): Telemetry App 화면(연결 코드·연결된 PC·연결 상태) 추가`

---

### Task 13: 문서 갱신 + 로컬 통합 확인

**Files:**
- Modify: `docs/00-overview.md`, `02-domain-design.md`, `03-entity-design.md`, `04-api-design.md`, `05-signalr-design.md`, `06-telemetry-design.md`, `07-roadmap.md`, `10-realtime-ingest.md` (매장·좌석·체크인 서술 → 개인 모드, P6~P11 로드맵)
- Modify: `docs/TESTING-local-e2e.md` (§2 "Swagger 체크인" → "Telemetry App에서 코드 발급 → `dotnet run -- pair <코드>`", §3 `ServerBaseUrl`, 자주 막히는 지점에 "다시 연결 필요"·429 추가)
- Modify: `docs/11-personal-mode.md` (Status → Implemented, 마이그레이션을 2건으로 나눈 이유 1줄), `docs/PROGRESS.md` (Phase 6 완료, 테스트 수, 다음 = P7)

- [ ] **Step 1: 전체 테스트** — `dotnet test backend/SimCenter.sln --nologo`, `dotnet test agent/SimCenter.Agent.sln --nologo`, `cd app; flutter analyze; flutter test` → 모두 PASS, 경고 0.
- [ ] **Step 2: 수동 통합 확인** — backend(`--launch-profile http`) · app(web-server 5960) · Agent Cli를 띄운다. 가입 → Telemetry App에서 코드 발급 → `dotnet run -- pair <코드>` → 웹 연결된 PC 목록에 PC 이름, 상태 "아직 받은 데이터가 없습니다" → (F1 25가 있으면) Time Trial 1랩 → Laps·Leaderboard·Dashboard 반영 → 웹에서 연결 해제 → Agent 로그 "다시 연결 필요".
- [ ] **Step 3: 문서 수정** — 위 파일 목록.
- [ ] **Step 4: 커밋** — `docs: P6 개인 모드 문서·로컬 E2E 가이드·진행 상황 갱신`
