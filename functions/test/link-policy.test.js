import assert from "node:assert/strict";
import test from "node:test";
import {
  LINK_HEARTBEAT_SECONDS,
  LINK_LIMITS,
  LINK_MAX_VISITOR_SECONDS,
  dwellDecision,
  linkExpiryDecision,
  linkLimit,
  openDecision,
  viewerHint,
} from "../src/link-policy.js";

test("link allowances stay intentional per plan", () => {
  assert.deepEqual(LINK_LIMITS, { free: 1, go: 5, pro: 25 });
  assert.equal(linkLimit("free"), 1);
  assert.equal(linkLimit("go"), 5);
  assert.equal(linkLimit("pro"), 25);
  assert.equal(linkLimit("unknown"), 1);
});

test("expiry must be in the future and inside the 92-day window", () => {
  const now = new Date("2026-07-17T12:00:00.000Z");
  assert.equal(linkExpiryDecision("2026-08-17T12:00:00.000Z", now).valid, true);
  assert.equal(linkExpiryDecision("2026-07-17T11:59:00.000Z", now).valid, false);
  assert.equal(linkExpiryDecision("2027-07-17T12:00:00.000Z", now).valid, false);
  assert.equal(linkExpiryDecision("not a date", now).valid, false);
});

test("a reload inside a sitting is not a fresh open; a later return is", () => {
  const now = new Date("2026-07-17T12:00:00.000Z");
  assert.equal(openDecision({ lastSeenAt: undefined, now }).freshOpen, true);
  assert.equal(
    openDecision({ lastSeenAt: new Date("2026-07-17T11:55:00.000Z"), now }).freshOpen,
    false
  );
  assert.equal(
    openDecision({ lastSeenAt: new Date("2026-07-17T11:20:00.000Z"), now }).freshOpen,
    true
  );
});

test("heartbeats accrue honest reading time and cap per visitor", () => {
  const now = new Date("2026-07-17T12:00:00.000Z");
  // A beat arriving on schedule earns a full heartbeat of reading.
  assert.equal(
    dwellDecision({
      currentSeconds: 30,
      lastSeenAt: new Date(now.getTime() - LINK_HEARTBEAT_SECONDS * 1000),
      now,
    }).addedSeconds,
    LINK_HEARTBEAT_SECONDS
  );
  // A beat after a long hidden gap still only earns one heartbeat.
  assert.equal(
    dwellDecision({
      currentSeconds: 30,
      lastSeenAt: new Date(now.getTime() - 10 * 60 * 1000),
      now,
    }).addedSeconds,
    LINK_HEARTBEAT_SECONDS
  );
  // A quick early beat earns only the elapsed seconds.
  assert.equal(
    dwellDecision({
      currentSeconds: 30,
      lastSeenAt: new Date(now.getTime() - 5000),
      now,
    }).addedSeconds,
    5
  );
  // The per-visitor total never exceeds the cap.
  assert.equal(
    dwellDecision({ currentSeconds: LINK_MAX_VISITOR_SECONDS, now }).addedSeconds,
    0
  );
  const nearCap = dwellDecision({
    currentSeconds: LINK_MAX_VISITOR_SECONDS - 4,
    lastSeenAt: new Date(now.getTime() - LINK_HEARTBEAT_SECONDS * 1000),
    now,
  });
  assert.equal(nearCap.addedSeconds, 4);
});

test("viewer hints stay coarse and never unique", () => {
  assert.equal(
    viewerHint("Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.0 Mobile/15E148 Safari/604.1"),
    "iPhone · Safari"
  );
  assert.equal(
    viewerHint("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"),
    "Windows · Chrome"
  );
  assert.equal(viewerHint(""), "Unknown device · browser");
});
