/// 설정 화면에서 고를 수 있는 IANA 타임존(docs/14 §3). 목록은 이곳 한 곳에만 둔다.
/// 저장만 한다 — 시각 표시는 아직 이 값을 쓰지 않는다(랭킹 기간 경계는 서버 설정, D-27). 새 패키지 없이 고정 목록으로 둔다.
const List<String> kTimeZoneIds = [
  'Asia/Seoul',
  'Asia/Tokyo',
  'Asia/Shanghai',
  'Asia/Singapore',
  'Australia/Sydney',
  'UTC',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Sao_Paulo',
];

/// 드롭다운 항목: 목록 + 목록에 없는 현재 값(다른 기기·API로 저장한 값도 잃지 않게 맨 앞에 보인다).
List<String> timeZoneChoices(String current) =>
    kTimeZoneIds.contains(current) ? kTimeZoneIds : [current, ...kTimeZoneIds];
