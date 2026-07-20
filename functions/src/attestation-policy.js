// Policy for evidence attestations: a former manager or colleague confirming a
// single claim from the evidence vault, through a one-use hosted link.
//
// What this feature can and cannot promise is decided here, because getting it
// wrong would be worse than not shipping it. ResumeStudio can prove that
// somebody holding the link responded, on a date, and record what they typed. It
// cannot prove who that person is. Nothing in this module — and nothing in the
// app or the hosted page — may describe a response as identity-verified.

/** A request that is not answered inside this window expires unanswered. A
 * verification ask that has been open for months is not evidence of anything. */
export const ATTESTATION_MAX_EXPIRY_DAYS = 30;
/** Once a request reaches one of these, it can never change again. This is what
 * stops a confirmation being quietly flipped, or answered twice. */
export const ATTESTATION_TERMINAL_STATUSES = new Set([
  "confirmed",
  "declined",
  "expired",
  "revoked",
]);
export const ATTESTATION_STATUSES = new Set(["pending", ...ATTESTATION_TERMINAL_STATUSES]);
/** The claim is written by the résumé owner and displayed to someone else, so it
 * is length-capped and stripped of markup before it is ever stored. */
export const ATTESTATION_CLAIM_MAX = 600;
export const ATTESTATION_NAME_MAX = 80;
export const ATTESTATION_ROLE_MAX = 120;
export const ATTESTATION_COMMENT_MAX = 500;

/**
 * Strips anything that could render as markup and collapses whitespace. Applied
 * to every free-text field in both directions, because both the owner's claim
 * and the verifier's comment end up on a public page.
 */
export function attestationText(value, maximum) {
  if (typeof value !== "string") return "";
  return value
    .replace(/[<>]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maximum);
}

/**
 * The claim an owner may ask someone to confirm. Returns null when there is
 * nothing usable to show a verifier.
 */
export function attestationClaim(value) {
  const claim = attestationText(value?.claim, ATTESTATION_CLAIM_MAX);
  if (claim.length < 8) return null;
  const context = attestationText(value?.context, ATTESTATION_ROLE_MAX);
  return { claim, context };
}

/**
 * Bounds a requested expiry. Mirrors `linkExpiryDecision` in shape so the two
 * hosted surfaces behave the same way.
 */
export function attestationExpiryDecision(expiresAt, now = new Date()) {
  const expiry = new Date(expiresAt);
  const latest = now.getTime() + ATTESTATION_MAX_EXPIRY_DAYS * 24 * 60 * 60 * 1000;
  const valid =
    Number.isFinite(expiry.getTime()) &&
    expiry.getTime() > now.getTime() &&
    expiry.getTime() <= latest;
  return { valid, expiry };
}

/**
 * What a verifier is allowed to submit. A response must be an explicit confirm
 * or decline — there is no default and no implied agreement from opening a page.
 */
export function attestationResponse(value) {
  const confirmed = value?.confirmed;
  if (typeof confirmed !== "boolean") return null;
  const name = attestationText(value?.name, ATTESTATION_NAME_MAX);
  if (name.length < 2) return null;
  return {
    status: confirmed ? "confirmed" : "declined",
    name,
    role: attestationText(value?.role, ATTESTATION_ROLE_MAX),
    comment: attestationText(value?.comment, ATTESTATION_COMMENT_MAX),
  };
}

/**
 * Whether a request may move to `next`. Terminal states are final, an expired
 * window can only ever become `expired`, and the owner may revoke only while the
 * request is still open.
 */
export function attestationTransition({ current, next, expiresAt, now = new Date() } = {}) {
  if (!ATTESTATION_STATUSES.has(current) || !ATTESTATION_STATUSES.has(next)) {
    return { allowed: false, reason: "unknown_status" };
  }
  if (ATTESTATION_TERMINAL_STATUSES.has(current)) {
    return { allowed: false, reason: "already_answered" };
  }
  const expiry = new Date(expiresAt);
  const hasExpired = Number.isFinite(expiry.getTime()) && expiry.getTime() <= now.getTime();
  if (hasExpired) {
    // A late answer is not accepted, but the record still settles honestly.
    return next === "expired"
      ? { allowed: true, reason: "expired" }
      : { allowed: false, reason: "expired" };
  }
  return { allowed: true, reason: "ok" };
}

/**
 * The public shape of a settled attestation. Deliberately omits the owner's
 * identity and the token: a page that shows a confirmation should not also
 * reveal who requested it or let it be replayed.
 */
export function attestationPublicRecord(record) {
  if (!record || record.status !== "confirmed") return null;
  return {
    status: "confirmed",
    claim: attestationText(record.claim, ATTESTATION_CLAIM_MAX),
    verifierName: attestationText(record.verifierName, ATTESTATION_NAME_MAX),
    verifierRole: attestationText(record.verifierRole, ATTESTATION_ROLE_MAX),
    comment: attestationText(record.comment, ATTESTATION_COMMENT_MAX),
    respondedAt: record.respondedAt || null,
    // Carried on every public record so the limitation travels with the claim
    // rather than living only in the app's UI copy.
    assurance: "responder_unverified",
  };
}
