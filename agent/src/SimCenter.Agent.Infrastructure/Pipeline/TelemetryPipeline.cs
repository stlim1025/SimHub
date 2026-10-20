using System.Buffers.Binary;
using Microsoft.Extensions.Logging;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Connection;
using SimCenter.Agent.Core.Telemetry.Frames;
using SimCenter.Agent.Infrastructure.Mapping;
using SimCenter.Agent.Infrastructure.Sinks;
using SimCenter.Agent.Infrastructure.Udp;

namespace SimCenter.Agent.Infrastructure.Pipeline;

/// <summary>
/// 전체 파이프라인 배선: UDP 수신 → F1 매핑 → (게임 에디션 판별) → 분석기 목록 판정 → 봉투 생성 → 싱크(docs/06 §1, docs/12 §5.5).
/// 분석기 목록(순서 무관, 분석기별 예외 격리): 분석기끼리 상태를 공유하지 않으므로 호출 순서에 의존하지 않고,
/// 한 분석기의 예외가 다른 분석기를 막지 않는다.
/// 데이터그램을 순차 처리한다(분석기가 상태 저장이라 단일 스레드 소비).
/// </summary>
public sealed class TelemetryPipeline
{
    private readonly UdpTelemetryListener _listener;
    private readonly F1PacketMapper _mapper;
    private readonly IReadOnlyList<ITelemetryAnalyzer> _analyzers;
    private readonly DomainEventFactory _factory;
    private readonly GameEditionDetector _edition;
    private readonly ITelemetrySink _sink;
    private readonly GameConnectionMonitor _monitor;
    private readonly ILogger<TelemetryPipeline> _logger;

    public TelemetryPipeline(
        UdpTelemetryListener listener,
        F1PacketMapper mapper,
        IEnumerable<ITelemetryAnalyzer> analyzers,
        DomainEventFactory factory,
        GameEditionDetector edition,
        ITelemetrySink sink,
        GameConnectionMonitor monitor,
        ILogger<TelemetryPipeline> logger)
    {
        _listener = listener;
        _mapper = mapper;
        _analyzers = analyzers.ToArray();
        _factory = factory;
        _edition = edition;
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
        IReadOnlyList<ITelemetryFrame> frames;
        try
        {
            frames = _mapper.Map(datagram.Span);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "패킷 매핑 실패 — 데이터그램 스킵");
            return;
        }

        await ProcessFramesAsync(frames, cancellationToken);
    }

    /// <summary>
    /// 프레임을 차례로 모든 분석기에 먹이고, 나온 이벤트를 봉투로 감싸 싱크로 보낸다.
    /// 분석기보다 먼저 게임 에디션 판별기에 보여 준다 — 같은 프레임에서 나온 이벤트도 판별 결과(F1 26)를 싣는다.
    /// 분석기마다 try/catch로 감싸 오류를 로그로 남기고 다음 분석기로 넘어간다(취소는 그대로 전파).
    /// </summary>
    internal async Task ProcessFramesAsync(IReadOnlyList<ITelemetryFrame> frames, CancellationToken cancellationToken)
    {
        foreach (var frame in frames)
        {
            _edition.Observe(frame);

            foreach (var analyzer in _analyzers)
            {
                try
                {
                    foreach (var domainEvent in analyzer.Process(frame))
                    {
                        var envelope = _factory.Wrap(domainEvent);
                        await _sink.EmitAsync(envelope, cancellationToken);
                    }
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    _logger.LogError(ex, "분석기 {Analyzer} 처리 실패 — 이 프레임({Frame})은 건너뛰고 다음 분석기로 진행", analyzer.GetType().Name, frame.GetType().Name);
                }
            }
        }
    }
}
