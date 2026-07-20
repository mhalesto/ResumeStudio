import test from "node:test";
import assert from "node:assert/strict";
import {
  ATTESTATION_CLAIM_MAX,
  ATTESTATION_MAX_EXPIRY_DAYS,
  attestationClaim,
  attestationExpiryDecision,
  attestationPublicRecord,
  attestationResponse,
  attestationText,
} from "../src/attestation-policy.js";
import { attestationTransition } from "../src/attestation-policy.js";

test("free text is stripped of markup and capped in both directions", () => {
  assert.equal(
    attestationText("<script>alert(1)</script> Led   the migration", 100),
    "scriptalert(1)/script Led the migration",
  );
  assert.equal(attestationText("x".repeat(999), 10), "x".repeat(10));
  assert.equal(attestationText(null, 10), "");
});

test("a claim must say something before anyone is asked to confirm it", () => {
  assert.equal(attestationClaim({ claim: "  " }), null);
  assert.equal(attestationClaim({ claim: "short" }), null);
  assert.deepEqual(
    attestationClaim({ claim: "Led the payments migration in 2024", context: "Northstar Works" }),
    { claim: "Led the payments migration in 2024", context: "Northstar Works" },
  );
  assert.equal(attestationClaim({ claim: "y".repeat(900) }).claim.length, ATTESTATION_CLAIM_MAX);
});

test("an expiry must be ahead and inside the window", () => {
  const now = new Date("2026-07-20T00:00:00Z");
  const withinWindow = new Date(now.getTime() + 10 * 24 * 60 * 60 * 1000);
  assert.equal(attestationExpiryDecision(withinWindow, now).valid, true);

  const past = new Date(now.getTime() - 1000);
  assert.equal(attestationExpiryDecision(past, now).valid, false);

  const tooFar = new Date(now.getTime() + (ATTESTATION_MAX_EXPIRY_DAYS + 1) * 24 * 60 * 60 * 1000);
  assert.equal(attestationExpiryDecision(tooFar, now).valid, false);
  assert.equal(attestationExpiryDecision("not a date", now).valid, false);
});

test("a response must be an explicit choice from a named person", () => {
  // Opening the page, or submitting nothing, is never an implied confirmation.
  assert.equal(attestationResponse({ name: "Sam Patel" }), null);
  assert.equal(attestationResponse({ confirmed: "yes", name: "Sam Patel" }), null);
  assert.equal(attestationResponse({ confirmed: true, name: "S" }), null);

  assert.deepEqual(
    attestationResponse({
      confirmed: true,
      name: "Sam Patel",
      role: "Former manager, Northstar Works",
      comment: "Accurate — Sam led that work.",
    }),
    {
      status: "confirmed",
      name: "Sam Patel",
      role: "Former manager, Northstar Works",
      comment: "Accurate — Sam led that work.",
    },
  );

  assert.equal(attestationResponse({ confirmed: false, name: "Sam Patel" }).status, "declined");
});

test("an answered request can never be answered again", () => {
  const expiresAt = new Date(Date.now() + 5 * 24 * 60 * 60 * 1000);
  const answered = attestationTransition({
    current: "confirmed", next: "declined", expiresAt,
  });
  assert.equal(answered.allowed, false);
  assert.equal(answered.reason, "already_answered");

  assert.equal(
    attestationTransition({ current: "revoked", next: "confirmed", expiresAt }).allowed,
    false,
  );
  assert.equal(
    attestationTransition({ current: "pending", next: "confirmed", expiresAt }).allowed,
    true,
  );
});

test("a late answer is refused but the record still settles", () => {
  const now = new Date("2026-07-20T00:00:00Z");
  const expiresAt = new Date(now.getTime() - 1000);
  assert.equal(
    attestationTransition({ current: "pending", next: "confirmed", expiresAt, now }).allowed,
    false,
  );
  assert.equal(
    attestationTransition({ current: "pending", next: "expired", expiresAt, now }).allowed,
    true,
  );
});

test("a public record carries the confirmation without the owner or the token", () => {
  const record = attestationPublicRecord({
    status: "confirmed",
    claim: "Led the payments migration in 2024",
    verifierName: "Sam Patel",
    verifierRole: "Former manager",
    comment: "Accurate.",
    respondedAt: "2026-07-19T10:00:00Z",
    token: "must-not-appear",
    ownerUid: "must-not-appear",
  });
  assert.equal(record.token, undefined);
  assert.equal(record.ownerUid, undefined);
  assert.equal(record.verifierName, "Sam Patel");
  // The limitation travels with the record, not only with the app's UI copy.
  assert.equal(record.assurance, "responder_unverified");
});

test("only a confirmation is ever published", () => {
  for (const status of ["pending", "declined", "expired", "revoked"]) {
    assert.equal(attestationPublicRecord({ status, claim: "Led the migration" }), null);
  }
});
