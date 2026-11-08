using System.Buffers.Binary;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using F1Game.UDP.Data;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// UDP 형식 2026(F1 25 2026 시즌팩) 바이트 → F1Game.UDP 25.1.1 구조체. 배치의 출처는 EA 2026 시즌팩 UDP 스펙을 옮긴 F1Game.UDP 26.0.0(MIT)의 구조체 정의다
/// (두 버전은 어셈블리 이름이 같아 한 프로세스에 함께 올릴 수 없다). 2025와 다른 곳:
/// 차 칸 22 → 24, Motion G-force float → int16(1/1000 g), Car Telemetry 엔진 온도 uint16 → uint8, Car Status에 랩당 ERS 회수 한도(float) 추가,
/// Participants의 드라이버·네트워크·팀 ID uint8 → uint16, Time Trial 팀 ID uint8 → uint16, Session 끝에 액티브 에어로·DRS 구역·출발 반응 시간(173바이트),
/// 충돌 이벤트에 강도 1바이트(공용체 안), 새 패킷 Car Telemetry 2(16).
/// 배치가 같은 칸(Lap Data·Car Damage·Car Setups·Final Classification)은 25.1.1 구조체로 바로 읽고(라이브러리도 바이트를 구조체에 그대로 복사한다),
/// 바뀐 칸은 2025 배치로 다시 써서 읽는다 — 매핑 코드는 형식과 무관하게 같은 구조체를 받는다. 팀·드라이버 ID는 1바이트에 담기지 않아 따로 돌려준다.
/// </summary>
internal static class Season2026Wire
{
    public const int MaxCars = 24;
    public const int HeaderSize = 29;
    public const int CarTelemetry2PacketId = 16;

    public const int MotionSize = HeaderSize + (MaxCars * MotionCarSize);
    public const int LapDataSize = HeaderSize + (MaxCars * LapDataCarSize) + TimeTrialCarIndexBytes;
    public const int CarTelemetrySize = HeaderSize + (MaxCars * TelemetryCarSize) + TelemetryTrailerBytes;
    public const int CarStatusSize = HeaderSize + (MaxCars * StatusCarSize);
    public const int CarDamageSize = HeaderSize + (MaxCars * DamageCarSize);
    public const int CarSetupsSize = HeaderSize + (MaxCars * SetupCarSize) + sizeof(float);
    public const int ClassificationSize = HeaderSize + CountByte + (MaxCars * ClassificationCarSize);
    public const int ParticipantsSize = HeaderSize + CountByte + (MaxCars * ParticipantCarSize);
    public const int LapPositionsSize = HeaderSize + LapPositionsPreamble + (MaxLapPositionLaps * MaxCars);
    public const int TimeTrialSize = HeaderSize + (TimeTrialSets * TimeTrialSetSize);
    public const int SessionSize = Season2025SessionSize + SessionTailSize;
    public const int CarTelemetry2Size = HeaderSize + (MaxCars * Telemetry2CarSize);

    /// <summary>Event 패킷은 크기가 그대로다(충돌 강도는 공용체 안의 남는 바이트).</summary>
    public const int EventSize = 45;

    public const int MaxLapPositionLaps = 50;

    private const int CountByte = 1;
    private const int TimeTrialCarIndexBytes = 2;   // m_timeTrialPBCarIdx · m_timeTrialRivalCarIdx
    private const int TelemetryTrailerBytes = 3;    // MFD 두 칸 · 추천 기어
    private const int TelemetryMfdBytes = 2;
    private const int LapPositionsPreamble = 2;     // 랩 수 · 시작 랩
    private const int TimeTrialSets = 3;

    // 차 한 대(2026)
    private const int MotionCarSize = 54;
    private const int LapDataCarSize = 57;
    private const int TelemetryCarSize = 59;
    private const int StatusCarSize = 59;
    private const int DamageCarSize = 46;
    private const int SetupCarSize = 50;
    private const int ClassificationCarSize = 46;
    private const int ParticipantCarSize = 60;
    private const int TimeTrialSetSize = 25;
    private const int Telemetry2CarSize = 10;

    // 같은 칸의 2025 배치(25.1.1 구조체 크기)
    private const int Motion2025Size = 60;
    private const int Telemetry2025Size = 60;
    private const int Status2025Size = 55;
    private const int Participant2025Size = 57;
    private const int TimeTrialSet2025Size = 24;

    /// <summary>Motion: 위치·속도(float 6) + 방향(int16 6) 뒤에 G-force 셋.</summary>
    private const int MotionGForceOffset = 36;
    private const int GForceAxes = 3;
    private const float GForceUnitsPerG = 1000f;

    /// <summary>Car Telemetry: 엔진 온도 앞까지(속도~안쪽 타이어 온도)의 바이트.</summary>
    private const int TelemetryEngineTempOffset = 38;

    /// <summary>Car Status: MGU-H 회수량 뒤에 랩당 회수 한도(float)가 끼어든다.</summary>
    private const int StatusHarvestLimitOffset = 50;

    /// <summary>Participants(2026): 드라이버(uint16) · 네트워크 ID(uint16) · 팀(uint16) 뒤가 2025의 "내 팀" 칸부터와 같다.</summary>
    private const int ParticipantDriverOffset = 1;
    private const int ParticipantNetworkIdOffset = 3;
    private const int ParticipantTeamOffset = 5;
    private const int ParticipantTailOffset = 7;
    private const int Participant2025TailOffset = 4;
    private const int ParticipantNameOffset = 10;
    private const int ParticipantNameBytes = 32;

    /// <summary>Time Trial 세트(2026): 차 번호 뒤 팀이 uint16.</summary>
    private const int TimeTrialTeamOffset = 1;
    private const int TimeTrialTailOffset = 3;
    private const int TimeTrial2025TailOffset = 2;

    /// <summary>2025 Session 패킷 크기 — 2026은 이 뒤에 꼬리를 붙였을 뿐 앞은 같다.</summary>
    private const int Season2025SessionSize = 753;
    private const int SessionTailSize = 173;
    private const int MaxActiveAeroZones = 8;
    private const int MaxDrsZones = 4;
    private const int ZoneBytes = 2 * sizeof(float);

    /// <summary>Event: 헤더 + 4글자 코드 뒤 충돌 상세(차 1 · 차 2 · 강도).</summary>
    private const int CollisionSeverityOffset = HeaderSize + 4 + 2;

    static Season2026Wire()
    {
        // 25.1.1 구조체를 바이트에서 바로 읽으므로 크기가 와이어 크기와 같아야 한다 — 다르면 칸이 밀린 값을 조용히 싣느니 바로 실패한다.
        EnsureSize<PacketHeader>(HeaderSize);
        EnsureSize<LapData>(LapDataCarSize);
        EnsureSize<CarDamageData>(DamageCarSize);
        EnsureSize<CarSetupData>(SetupCarSize);
        EnsureSize<FinalClassificationData>(ClassificationCarSize);
        EnsureSize<CarMotionData>(Motion2025Size);
        EnsureSize<CarTelemetryData>(Telemetry2025Size);
        EnsureSize<CarStatusData>(Status2025Size);
        EnsureSize<ParticipantData>(Participant2025Size);
        EnsureSize<TimeTrialDataSet>(TimeTrialSet2025Size);
    }

    public static PacketHeader Header(ReadOnlySpan<byte> datagram) => MemoryMarshal.Read<PacketHeader>(datagram);

    public static ReadOnlySpan<LapData> LapData(ReadOnlySpan<byte> datagram) => Cars<LapData>(datagram, HeaderSize, LapDataCarSize);

    public static (byte PersonalBest, byte Rival) TimeTrialCarIndexes(ReadOnlySpan<byte> datagram)
    {
        var offset = HeaderSize + (MaxCars * LapDataCarSize);
        return (datagram[offset], datagram[offset + 1]);
    }

    public static ReadOnlySpan<CarDamageData> CarDamage(ReadOnlySpan<byte> datagram) => Cars<CarDamageData>(datagram, HeaderSize, DamageCarSize);

    public static ReadOnlySpan<CarSetupData> CarSetups(ReadOnlySpan<byte> datagram) => Cars<CarSetupData>(datagram, HeaderSize, SetupCarSize);

    public static float NextFrontWingValue(ReadOnlySpan<byte> datagram) =>
        BinaryPrimitives.ReadSingleLittleEndian(datagram[(HeaderSize + (MaxCars * SetupCarSize))..]);

    public static ReadOnlySpan<FinalClassificationData> Classification(ReadOnlySpan<byte> datagram) =>
        Cars<FinalClassificationData>(datagram, HeaderSize + CountByte, ClassificationCarSize);

    /// <summary>G-force(1/1000 g int16)를 g(float)로 바꿔 2025 배치에 넣는다.</summary>
    public static CarMotionData[] Motion(ReadOnlySpan<byte> datagram)
    {
        const int gForceEnd2026 = MotionGForceOffset + (GForceAxes * sizeof(short));
        const int gForceEnd2025 = MotionGForceOffset + (GForceAxes * sizeof(float));
        var cars = new CarMotionData[MaxCars];
        Span<byte> buffer = stackalloc byte[Motion2025Size];
        for (var i = 0; i < MaxCars; i++)
        {
            var source = Car(datagram, HeaderSize, MotionCarSize, i);
            source[..MotionGForceOffset].CopyTo(buffer);
            for (var axis = 0; axis < GForceAxes; axis++)
            {
                var raw = BinaryPrimitives.ReadInt16LittleEndian(source[(MotionGForceOffset + (axis * sizeof(short)))..]);
                BinaryPrimitives.WriteSingleLittleEndian(buffer[(MotionGForceOffset + (axis * sizeof(float)))..], raw / GForceUnitsPerG);
            }

            source[gForceEnd2026..].CopyTo(buffer[gForceEnd2025..]);
            cars[i] = MemoryMarshal.Read<CarMotionData>(buffer);
        }

        return cars;
    }

    /// <summary>엔진 온도(uint8)를 2025의 uint16 칸으로 넓힌다.</summary>
    public static CarTelemetryData[] CarTelemetry(ReadOnlySpan<byte> datagram)
    {
        var cars = new CarTelemetryData[MaxCars];
        Span<byte> buffer = stackalloc byte[Telemetry2025Size];
        for (var i = 0; i < MaxCars; i++)
        {
            var source = Car(datagram, HeaderSize, TelemetryCarSize, i);
            source[..TelemetryEngineTempOffset].CopyTo(buffer);
            BinaryPrimitives.WriteUInt16LittleEndian(buffer[TelemetryEngineTempOffset..], source[TelemetryEngineTempOffset]);
            source[(TelemetryEngineTempOffset + 1)..].CopyTo(buffer[(TelemetryEngineTempOffset + sizeof(ushort))..]);
            cars[i] = MemoryMarshal.Read<CarTelemetryData>(buffer);
        }

        return cars;
    }

    public static byte SuggestedGear(ReadOnlySpan<byte> datagram) => datagram[HeaderSize + (MaxCars * TelemetryCarSize) + TelemetryMfdBytes];

    /// <summary>랩당 ERS 회수 한도를 빼고 2025 배치로 읽는다(한도는 <see cref="ErsHarvestLimitPerLap"/>).</summary>
    public static CarStatusData[] CarStatus(ReadOnlySpan<byte> datagram)
    {
        var cars = new CarStatusData[MaxCars];
        Span<byte> buffer = stackalloc byte[Status2025Size];
        for (var i = 0; i < MaxCars; i++)
        {
            var source = Car(datagram, HeaderSize, StatusCarSize, i);
            source[..StatusHarvestLimitOffset].CopyTo(buffer);
            source[(StatusHarvestLimitOffset + sizeof(float))..].CopyTo(buffer[StatusHarvestLimitOffset..]);
            cars[i] = MemoryMarshal.Read<CarStatusData>(buffer);
        }

        return cars;
    }

    /// <summary>그 차의 이번 랩 ERS 회수 한도(J).</summary>
    public static float ErsHarvestLimitPerLap(ReadOnlySpan<byte> datagram, int carIndex) =>
        BinaryPrimitives.ReadSingleLittleEndian(Car(datagram, HeaderSize, StatusCarSize, carIndex)[StatusHarvestLimitOffset..]);

    /// <summary>참가자 칸. 25.1.1 구조체의 드라이버·네트워크·팀 칸(1바이트)은 비우고 실제 값은 칸 밖에 싣는다.</summary>
    public static ParticipantSlot[] Participants(ReadOnlySpan<byte> datagram)
    {
        var slots = new ParticipantSlot[MaxCars];
        Span<byte> buffer = stackalloc byte[Participant2025Size];
        for (var i = 0; i < MaxCars; i++)
        {
            var source = Car(datagram, HeaderSize + CountByte, ParticipantCarSize, i);
            buffer.Clear();
            buffer[0] = source[0];
            source[ParticipantTailOffset..].CopyTo(buffer[Participant2025TailOffset..]);
            var driver = BinaryPrimitives.ReadUInt16LittleEndian(source[ParticipantDriverOffset..]);
            slots[i] = new ParticipantSlot(
                MemoryMarshal.Read<ParticipantData>(buffer),
                Name: Encoding.UTF8.GetString(source.Slice(ParticipantNameOffset, ParticipantNameBytes)),
                DriverId: driver,
                IsNetworkHuman: driver == ushort.MaxValue,
                NetworkId: BinaryPrimitives.ReadUInt16LittleEndian(source[ParticipantNetworkIdOffset..]),
                TeamId: BinaryPrimitives.ReadUInt16LittleEndian(source[ParticipantTeamOffset..]));
        }

        return slots;
    }

    /// <summary>Time Trial 세트 셋(이 세션 베스트 · 개인 베스트 · 라이벌). 팀 ID는 칸 밖에 싣는다.</summary>
    public static (TimeTrialSet SessionBest, TimeTrialSet PersonalBest, TimeTrialSet Rival) TimeTrial(ReadOnlySpan<byte> datagram) =>
        (TimeTrialSetAt(datagram, 0), TimeTrialSetAt(datagram, 1), TimeTrialSetAt(datagram, 2));

    public static (int NumberOfLaps, int StartingLap) LapPositionsRange(ReadOnlySpan<byte> datagram) =>
        (datagram[HeaderSize], datagram[HeaderSize + 1]);

    /// <summary>랩 하나의 차별 순위(24칸).</summary>
    public static ReadOnlySpan<byte> LapPositionsRow(ReadOnlySpan<byte> datagram, int lapIndex) =>
        datagram.Slice(HeaderSize + LapPositionsPreamble + (lapIndex * MaxCars), MaxCars);

    public static Season2026SessionTail SessionTail(ReadOnlySpan<byte> datagram)
    {
        var tail = datagram[Season2025SessionSize..];
        var offset = 0;
        var activeAeroTrackStatus = tail[offset++];
        var full = Zones(tail, ref offset, MaxActiveAeroZones);
        var partial = Zones(tail, ref offset, MaxActiveAeroZones);
        var drs = Zones(tail, ref offset, MaxDrsZones);
        var startReactionTime = BinaryPrimitives.ReadSingleLittleEndian(tail[offset..]);
        offset += sizeof(float);
        return new Season2026SessionTail(
            activeAeroTrackStatus,
            full,
            partial,
            drs,
            startReactionTime,
            AntiLockBrakesAssist: tail[offset],
            TractionControlAssist: tail[offset + 1]);
    }

    public static Season2026CarTelemetry2 CarTelemetry2(ReadOnlySpan<byte> datagram, int carIndex)
    {
        var car = Car(datagram, HeaderSize, Telemetry2CarSize, carIndex);
        return new Season2026CarTelemetry2(
            ActiveAeroMode: car[0],
            ActiveAeroAvailable: car[1] != 0,
            ActiveAeroActivationDistance: BinaryPrimitives.ReadUInt16LittleEndian(car[2..]),
            OvertakeAvailable: car[4] != 0,
            OvertakeActive: car[5] != 0,
            OvertakeActivationDistance: BinaryPrimitives.ReadUInt16LittleEndian(car[6..]),
            Regulations2026Applicable: car[8] != 0,
            IsDrivingWrongWay: car[9] != 0);
    }

    /// <summary>충돌(COLL) 이벤트의 강도(0 낮음 · 1 중간 · 2 높음).</summary>
    public static byte CollisionSeverity(ReadOnlySpan<byte> datagram) => datagram[CollisionSeverityOffset];

    private static TimeTrialSet TimeTrialSetAt(ReadOnlySpan<byte> datagram, int index)
    {
        var source = Car(datagram, HeaderSize, TimeTrialSetSize, index);
        Span<byte> buffer = stackalloc byte[TimeTrialSet2025Size];
        buffer.Clear();
        buffer[0] = source[0];
        source[TimeTrialTailOffset..].CopyTo(buffer[TimeTrial2025TailOffset..]);
        return new TimeTrialSet(MemoryMarshal.Read<TimeTrialDataSet>(buffer), BinaryPrimitives.ReadUInt16LittleEndian(source[TimeTrialTeamOffset..]));
    }

    /// <summary>개수 1바이트 + 구역 칸(시작·끝 랩 비율 float 2개). 개수를 넘는 칸은 쓰레기라 읽지 않는다.</summary>
    private static (float Start, float End)[] Zones(ReadOnlySpan<byte> tail, ref int offset, int slots)
    {
        var count = Math.Min((int)tail[offset++], slots);
        var zones = new (float Start, float End)[count];
        for (var i = 0; i < count; i++)
        {
            var zone = tail[(offset + (i * ZoneBytes))..];
            zones[i] = (BinaryPrimitives.ReadSingleLittleEndian(zone), BinaryPrimitives.ReadSingleLittleEndian(zone[sizeof(float)..]));
        }

        offset += slots * ZoneBytes;
        return zones;
    }

    private static ReadOnlySpan<T> Cars<T>(ReadOnlySpan<byte> datagram, int offset, int carSize)
        where T : unmanaged => MemoryMarshal.Cast<byte, T>(datagram.Slice(offset, MaxCars * carSize));

    private static ReadOnlySpan<byte> Car(ReadOnlySpan<byte> datagram, int offset, int carSize, int index) =>
        datagram.Slice(offset + (index * carSize), carSize);

    private static void EnsureSize<T>(int expected)
        where T : unmanaged
    {
        if (Unsafe.SizeOf<T>() != expected)
        {
            throw new InvalidOperationException($"F1Game.UDP {typeof(T).Name} 크기 {Unsafe.SizeOf<T>()} ≠ 와이어 {expected}바이트 — 라이브러리 버전이 바뀌었는지 확인하세요");
        }
    }
}

/// <summary>Session(2026) 끝에 붙은 값 — 액티브 에어로 구역(전체·부분)·DRS 구역(랩 비율), 출발 반응 시간(초), 보조 장치 설정(게임 원시 값).</summary>
internal sealed record Season2026SessionTail(
    byte ActiveAeroTrackStatus,
    IReadOnlyList<(float Start, float End)> ActiveAeroZonesFull,
    IReadOnlyList<(float Start, float End)> ActiveAeroZonesPartial,
    IReadOnlyList<(float Start, float End)> DrsZones,
    float StartReactionTime,
    byte AntiLockBrakesAssist,
    byte TractionControlAssist);

/// <summary>Car Telemetry 2(16, 2026 전용) 한 차 — 액티브 에어로(0 코너 · 1 직선)·오버테이크 모드. 거리는 m.</summary>
internal readonly record struct Season2026CarTelemetry2(
    byte ActiveAeroMode,
    bool ActiveAeroAvailable,
    ushort ActiveAeroActivationDistance,
    bool OvertakeAvailable,
    bool OvertakeActive,
    ushort OvertakeActivationDistance,
    bool Regulations2026Applicable,
    bool IsDrivingWrongWay);
