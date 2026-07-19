export const DAILY_IMPORT_LIMITS = Object.freeze({ free: 1, go: 1, pro: 2 });
export const PHOTO_IMPORT_IMAGE_LIMITS = Object.freeze({ free: 2, go: 5, pro: 5 });

export function dailyImportLimit(tier) {
  return DAILY_IMPORT_LIMITS[tier] || DAILY_IMPORT_LIMITS.free;
}

export function photoImportImageLimit(tier) {
  return PHOTO_IMPORT_IMAGE_LIMITS[tier] || PHOTO_IMPORT_IMAGE_LIMITS.free;
}

export function dayKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

export function startOfNextUTCDay(date = new Date()) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1));
}

export function dailyImportDecision({ tier, used, now = new Date() }) {
  const safeUsed = Math.max(0, Number(used) || 0);
  const limit = dailyImportLimit(tier);
  const allowed = safeUsed < limit;
  const updatedUsed = allowed ? safeUsed + 1 : safeUsed;
  return {
    allowed,
    updatedUsed,
    allowance: {
      tier: DAILY_IMPORT_LIMITS[tier] ? tier : "free",
      importsUsed: updatedUsed,
      importsLimit: limit,
      importsRemaining: Math.max(0, limit - updatedUsed),
      resetAt: startOfNextUTCDay(now),
    },
  };
}
