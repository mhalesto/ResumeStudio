// Policy for trackable résumé links: plan allowances, expiry bounds, visitor
// identity, and how dwell-time heartbeats accumulate into honest view stats.
// Pure functions, so the numbers the app promises are pinned by tests.

export const LINK_LIMITS = { free: 1, go: 5, pro: 25 };
export const LINK_MAX_EXPIRY_DAYS = 92;
export const LINK_HEARTBEAT_SECONDS = 12;
// One visitor session stops accruing after an hour — a tab left open is not
// an hour of reading.
export const LINK_MAX_VISITOR_SECONDS = 60 * 60;
// A returning visitor counts as a new open once this much quiet has passed.
export const LINK_FRESH_OPEN_GAP_MS = 30 * 60 * 1000;

export function linkLimit(tier) {
  return LINK_LIMITS[tier] ?? LINK_LIMITS.free;
}

/**
 * Validates a requested expiry: must parse, be in the future, and fall within
 * the maximum window. Returns { valid, expiry }.
 */
export function linkExpiryDecision(expiresAt, now = new Date()) {
  const expiry = new Date(expiresAt);
  const latest = now.getTime() + LINK_MAX_EXPIRY_DAYS * 24 * 60 * 60 * 1000;
  const valid =
    Number.isFinite(expiry.getTime()) &&
    expiry.getTime() > now.getTime() &&
    expiry.getTime() <= latest;
  return { valid, expiry };
}

/**
 * A coarse, non-identifying description of the viewer's device from the
 * user-agent — "iPhone · Safari", "Windows · Chrome". Never versions, never
 * anything unique.
 */
export function viewerHint(userAgent) {
  const agent = String(userAgent || "");
  const device = agent.includes("iPhone") ? "iPhone"
    : agent.includes("iPad") ? "iPad"
    : agent.includes("Android") ? "Android"
    : agent.includes("Windows") ? "Windows"
    : agent.includes("Macintosh") ? "Mac"
    : agent.includes("Linux") ? "Linux"
    : "Unknown device";
  const browser = agent.includes("Edg/") ? "Edge"
    : agent.includes("OPR/") || agent.includes("Opera") ? "Opera"
    : agent.includes("Firefox/") ? "Firefox"
    : agent.includes("Chrome/") ? "Chrome"
    : agent.includes("Safari/") ? "Safari"
    : "browser";
  return `${device} · ${browser}`;
}

/**
 * How a page open updates a visitor record: the first sight of a visitor, or
 * a return after a long gap, counts as a fresh open; a reload inside the same
 * sitting does not inflate the count.
 */
export function openDecision({ lastSeenAt, now = new Date() } = {}) {
  if (!lastSeenAt) return { freshOpen: true };
  const gap = now.getTime() - new Date(lastSeenAt).getTime();
  return { freshOpen: !(gap >= 0 && gap < LINK_FRESH_OPEN_GAP_MS) };
}

/**
 * How much reading time one heartbeat is worth. Beats arrive every
 * LINK_HEARTBEAT_SECONDS while the page is visible; anything slower means the
 * tab was hidden, so only a single heartbeat's worth is credited, and a
 * visitor's total is capped.
 */
export function dwellDecision({ currentSeconds = 0, lastSeenAt, now = new Date() } = {}) {
  if (currentSeconds >= LINK_MAX_VISITOR_SECONDS) return { addedSeconds: 0 };
  let credit = LINK_HEARTBEAT_SECONDS;
  if (lastSeenAt) {
    const gapSeconds = (now.getTime() - new Date(lastSeenAt).getTime()) / 1000;
    if (gapSeconds >= 0 && gapSeconds < LINK_HEARTBEAT_SECONDS) {
      credit = Math.round(gapSeconds);
    }
  }
  const addedSeconds = Math.max(
    0, Math.min(credit, LINK_MAX_VISITOR_SECONDS - currentSeconds)
  );
  return { addedSeconds };
}
