import '../../../core/widgets/track_picker.dart';
import '../domain/ranking_models.dart';

/// 트랙 마스터 → 트랙 메뉴 항목(Laps·Leaderboard 공용).
TrackChoice trackChoiceOf(Track track) =>
    TrackChoice(id: track.trackId, name: track.name, countryCode: track.countryCode);

/// `GET /tracks` 순서(캘린더 순서) 그대로의 메뉴 항목.
List<TrackChoice> trackChoicesOf(List<Track> tracks) => [for (final track in tracks) trackChoiceOf(track)];
