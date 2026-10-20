using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 세션별 게임 에디션 판별(상태 저장, 순수 로직). 새 세션(세션 참조가 바뀜)이면 설정 기본값으로 돌아가고,
/// 그 세션의 참가자 프레임에 2026 팀 ID(<see cref="GameEditions.Is2026TeamId"/>)가 한 대라도 있으면 그 세션이 끝날 때까지 <see cref="GameEditions.F1_26"/>이다.
/// 내 팀이 커스텀인 My Team 커리어도 AI 라이벌이 2026 팀이라 잡힌다. 파이프라인이 분석기보다 먼저 프레임을 보여 준다(단일 스레드 기록).
/// 트레이 화면이 다른 스레드에서 <see cref="GameCode"/>를 읽으므로 값은 volatile로 둔다.
/// </summary>
public sealed class GameEditionDetector : IGameCodeSource
{
    private readonly string _defaultGameCode;
    private string? _sessionRef;
    private volatile string _gameCode;

    public GameEditionDetector(string defaultGameCode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(defaultGameCode);
        _defaultGameCode = defaultGameCode;
        _gameCode = defaultGameCode;
    }

    /// <summary>지금 세션의 게임 코드.</summary>
    public string GameCode => _gameCode;

    /// <summary>프레임 하나를 본다. 세션·참가자 프레임만 상태를 바꾼다.</summary>
    public void Observe(ITelemetryFrame frame)
    {
        switch (frame)
        {
            case SessionFrame session:
                EnterSession(session.SessionRef);
                break;
            case ParticipantsFrame participants:
                EnterSession(participants.SessionRef);
                if (participants.Participants.Any(p => GameEditions.Is2026TeamId(p.TeamId)))
                {
                    _gameCode = GameEditions.F1_26;
                }

                break;
        }
    }

    private void EnterSession(string sessionRef)
    {
        if (sessionRef == _sessionRef)
        {
            return;
        }

        _sessionRef = sessionRef;
        _gameCode = _defaultGameCode;
    }
}
