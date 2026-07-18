import assert from "node:assert/strict";
import test from "node:test";
import {
  PROFILE_RESERVED,
  profileIsBranded,
  sanitizeProfileLinks,
  validHandle,
} from "../src/profile-policy.js";

test("handles accept clean vanity slugs", () => {
  assert.equal(validHandle("halalisani"), true);
  assert.equal(validHandle("jane-doe"), true);
  assert.equal(validHandle("dev2026"), true);
  assert.equal(validHandle("a1b"), true); // minimum length 3
});

test("handles reject malformed, reserved, and unsafe slugs", () => {
  assert.equal(validHandle("ab"), false); // too short
  assert.equal(validHandle("a".repeat(31)), false); // too long
  assert.equal(validHandle("-jane"), false); // leading hyphen
  assert.equal(validHandle("jane-"), false); // trailing hyphen
  assert.equal(validHandle("ja--ne"), false); // doubled hyphen
  assert.equal(validHandle("Jane"), false); // uppercase not folded
  assert.equal(validHandle("jane.doe"), false); // illegal character
  assert.equal(validHandle("admin"), false); // reserved
  assert.equal(validHandle("cv"), false); // reserved route word
  assert.equal(validHandle(123), false);
});

test("reserved set covers the public route words", () => {
  for (const word of ["p", "api", "profile", "resumestudio"]) {
    assert.equal(PROFILE_RESERVED.has(word), true);
  }
});

test("profile links keep only labelled http(s) rows, capped at six", () => {
  const links = sanitizeProfileLinks([
    { label: "LinkedIn", url: "https://linkedin.com/in/jane" },
    { label: "Portfolio", url: "http://jane.dev" },
    { label: "No scheme", url: "jane.dev" }, // dropped: not http(s)
    { label: "", url: "https://valid.com" }, // dropped: no label
    { label: "Bad", url: "not a url" }, // dropped: unparseable
    { label: "One", url: "https://1.com" },
    { label: "Two", url: "https://2.com" },
    { label: "Three", url: "https://3.com" },
    { label: "Four", url: "https://4.com" }, // seventh valid row → beyond cap
  ]);
  assert.equal(links.length, 6);
  assert.equal(links[0].label, "LinkedIn");
  assert.equal(links[0].url, "https://linkedin.com/in/jane");
  assert.ok(links.every((link) => /^https?:\/\//.test(link.url)));
});

test("non-array or empty link input yields no links", () => {
  assert.deepEqual(sanitizeProfileLinks(undefined), []);
  assert.deepEqual(sanitizeProfileLinks("nope"), []);
  assert.deepEqual(sanitizeProfileLinks([]), []);
});

test("branding follows the plan: free branded, paid clean", () => {
  assert.equal(profileIsBranded("free"), true);
  assert.equal(profileIsBranded("unknown"), true);
  assert.equal(profileIsBranded("go"), false);
  assert.equal(profileIsBranded("pro"), false);
});
