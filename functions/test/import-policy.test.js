import assert from "node:assert/strict";
import test from "node:test";
import {
  DAILY_IMPORT_LIMITS,
  PHOTO_IMPORT_IMAGE_LIMITS,
  dailyImportDecision,
  dailyImportLimit,
  dayKey,
  photoImportImageLimit,
  startOfNextUTCDay,
} from "../src/import-policy.js";

test("free imports allow one successful request each UTC day", () => {
  const now = new Date("2026-07-16T21:30:00.000Z");
  const first = dailyImportDecision({ tier: "free", used: 0, now });
  assert.equal(first.allowed, true);
  assert.equal(first.allowance.importsRemaining, 0);

  const second = dailyImportDecision({ tier: "free", used: first.updatedUsed, now });
  assert.equal(second.allowed, false);
  assert.equal(second.updatedUsed, 1);
  assert.equal(second.allowance.importsRemaining, 0);
});

test("plans receive the intentional daily and per-photo-import limits", () => {
  assert.deepEqual(DAILY_IMPORT_LIMITS, { free: 1, go: 1, pro: 2 });
  assert.deepEqual(PHOTO_IMPORT_IMAGE_LIMITS, { free: 2, go: 5, pro: 5 });
  assert.equal(dailyImportLimit("go"), 1);
  assert.equal(dailyImportLimit("pro"), 2);
  assert.equal(dailyImportLimit("unknown"), 1);
  assert.equal(photoImportImageLimit("free"), 2);
  assert.equal(photoImportImageLimit("go"), 5);
  assert.equal(photoImportImageLimit("pro"), 5);
  assert.equal(photoImportImageLimit("unknown"), 2);
});

test("daily allowance resets at the next UTC midnight", () => {
  const now = new Date("2026-12-31T23:59:59.000Z");
  assert.equal(dayKey(now), "2026-12-31");
  assert.equal(startOfNextUTCDay(now).toISOString(), "2027-01-01T00:00:00.000Z");
});
