import assert from "node:assert/strict";
import test from "node:test";
import {
  DAILY_IMPORT_LIMITS,
  dailyImportDecision,
  dailyImportLimit,
  dayKey,
  startOfNextUTCDay,
} from "../src/import-policy.js";

test("free imports allow five successful requests each UTC day", () => {
  const now = new Date("2026-07-16T21:30:00.000Z");
  let used = 0;
  for (let attempt = 1; attempt <= 5; attempt += 1) {
    const decision = dailyImportDecision({ tier: "free", used, now });
    assert.equal(decision.allowed, true);
    used = decision.updatedUsed;
    assert.equal(decision.allowance.importsRemaining, 5 - attempt);
  }

  const sixth = dailyImportDecision({ tier: "free", used, now });
  assert.equal(sixth.allowed, false);
  assert.equal(sixth.updatedUsed, 5);
  assert.equal(sixth.allowance.importsRemaining, 0);
});

test("paid plans and unknown tiers receive the intentional limits", () => {
  assert.deepEqual(DAILY_IMPORT_LIMITS, { free: 5, go: 20, pro: 30 });
  assert.equal(dailyImportLimit("go"), 20);
  assert.equal(dailyImportLimit("pro"), 30);
  assert.equal(dailyImportLimit("unknown"), 5);
});

test("daily allowance resets at the next UTC midnight", () => {
  const now = new Date("2026-12-31T23:59:59.000Z");
  assert.equal(dayKey(now), "2026-12-31");
  assert.equal(startOfNextUTCDay(now).toISOString(), "2027-01-01T00:00:00.000Z");
});
