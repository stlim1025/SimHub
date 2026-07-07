using System.Buffers.Binary;
using Microsoft.Extensions.Logging;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Connection;
using SimCenter.Agent.Infrastructure.Mapping;
using SimCenter.Agent.Infrastructure.Sinks;
using SimCenter.Agent.Infrastructure.Udp;

namespace SimCenter.Agent.Infrastructure.Pipeline;

/// <summary>
/// 전체 파이프라인 배선: UDP 수신 → F1 매핑 → LapAnalyzer 판정 → 봉투 생성 → 싱크(docs/06 §1).
/// 데이터그램을 순차 처리한다(LapAnalyzer가 상태 저장이라 단일 스레드 소비).
/// </summary>
public sealed class TelemetryPipeline
{
    private readonly UdpTelemetryListener _listener;
    private readonly F1PacketMapper _mapper;
    private readonly LapAnalyzer _analyzer;
    private readonly DomainEventFactory _factory;
    private readonly ITelemetrySink _sink;
    private readonly GameConnectionMonitor _monitor;
    private readonly ILogger<TelemetryPipeline> _logger;

    public TelemetryPipeline(
        UdpTelemetryListener listener,
        F1PacketMapper mapper,
        LapAnalyzer analyzer,
        DomainEventFactory factory,
        ITelemetrySink sink,
        GameConnectionMonitor monitor,
        ILogger<TelemetryPipeline> logger)
    {
        _listener = listener;
        _mapper = mapper;
        _analyzer = analyzer;
        _factory = factory;
        _sink = sink;
        _monitor = monitor;
        _logger = logger;
    }

    public Task RunAsync(CancellationToken cancellationToken) => _listener.RunAsync(HandleDatagramAsync, cancellationToken);

    private async Task HandleDatagramAsync(ReadOnlyMemory<byte> datagram, CancellationToken cancellationToken)
    {
        // 데이터그램 도착 = "게임이 보내는 중" 신호(파싱 성공과 무관). 앞 2바이트가 m_packetFormat(uint16 LE).
        int? packetFormat = datagram.Length >= 2 ? BinaryPrimitives.ReadUInt16LittleEndian(datagram.Span) : null;
        _monitor.RecordDatagram(packetFormat);

        // 매핑은 동기(Span) — await 이전에 프레임 목록으로 물질화한다.
        IReadOnlyList<Core.Telemetry.Frames.ITelemetryFrame> frames;
        try
        {
            frames = _mapper.Map(datagram.Span);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "패킷 매핑 실패 — 데이터그램 스킵");
            return;
        }

        foreach (var frame in frames)
        {
            foreach (var domainEvent in _analyzer.Process(frame))
            {
                var envelope = _factory.Wrap(domainEvent);
                await _sink.EmitAsync(envelope, cancellationToken);
            }
        }
    }
}
