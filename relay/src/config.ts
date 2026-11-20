export const RELAY = {
  name: "ChessCast relay",
  maxBlob: 60 * 1024,
  codeLength: 6,
  codeChars: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789",
  queuePrefix: "MATCH_",
  rankedQueuePrefix: "RANK_",
  ratingRange: 100,
  ratingRangeExpanded: 500,
  ratingExpandMs: 60 * 1000,
  ratingMin: 0,
  ratingMax: 9999,
};
