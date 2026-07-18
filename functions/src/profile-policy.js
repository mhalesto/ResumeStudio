// Pure helpers for the hosted personal CV page (the vanity /p/<handle> URL).
// Kept side-effect free so the handle rules and link sanitising are pinned by
// tests, exactly like link-policy.js.

// Handles that would collide with a route, look official, or read as spam. A
// handle is matched case-insensitively after lowercasing.
export const PROFILE_RESERVED = new Set([
  "admin", "administrator", "api", "app", "apps", "cv", "p", "www", "mail",
  "support", "help", "about", "terms", "privacy", "legal", "contact",
  "login", "logout", "signin", "signup", "register", "account", "accounts",
  "settings", "profile", "profiles", "resume", "resumes", "resumestudio",
  "studio", "home", "search", "explore", "new", "edit", "delete", "static",
  "assets", "favicon", "robots", "sitemap", "null", "undefined", "root",
]);

/**
 * A handle is 3–30 characters, lowercase alphanumeric and single hyphens, with
 * no leading, trailing, or doubled hyphen, and is not reserved. Uppercase is
 * rejected rather than folded so the stored handle always matches the URL.
 */
export function validHandle(value) {
  if (typeof value !== "string") return false;
  if (!/^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$/.test(value)) return false;
  if (value.includes("--")) return false;
  return !PROFILE_RESERVED.has(value);
}

/**
 * At most six external links, each an http(s) URL with a short label. Anything
 * malformed is dropped rather than rejecting the whole publish, so one bad row
 * never blocks a page going live.
 */
export function sanitizeProfileLinks(value, { maxLinks = 6, maxLabel = 40, maxURL = 400 } = {}) {
  if (!Array.isArray(value)) return [];
  const links = [];
  // Scan a bounded prefix so a hostile array cannot cost much, but count the
  // cap against *valid* rows so a bad row never crowds out a good one.
  for (const entry of value.slice(0, 50)) {
    if (links.length >= maxLinks) break;
    const label = typeof entry?.label === "string" ? entry.label.trim().slice(0, maxLabel) : "";
    const rawURL = typeof entry?.url === "string" ? entry.url.trim().slice(0, maxURL) : "";
    if (!label || !/^https?:\/\//i.test(rawURL)) continue;
    let normalized;
    try { normalized = new URL(rawURL).toString(); } catch { continue; }
    links.push({ label, url: normalized });
  }
  return links;
}

/** Free pages carry a "Made with ResumeStudio" footer; Go and Pro remove it. */
export function profileIsBranded(tier) {
  return tier !== "go" && tier !== "pro";
}
