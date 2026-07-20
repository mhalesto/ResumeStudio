// Policy for outcome benchmarks: the only cohort dimensions that exist, what an
// installation is allowed to contribute, and when a cohort has enough distinct
// contributors to be published at all.
//
// Benchmarks are the one feature that reads across users, so the rules that keep
// them non-identifying live here as pure functions and are pinned by tests. The
// contribution shape carries counts only — never résumé content, employer names,
// job titles, URLs, or anything free-text.

/** Coarse role families. Deliberately broad: a narrow family in a small market
 * is a person, not a cohort. */
export const BENCHMARK_ROLE_FAMILIES = [
  "engineering",
  "dataAnalytics",
  "design",
  "product",
  "marketing",
  "sales",
  "customerSuccess",
  "financeAccounting",
  "peopleOperations",
  "operationsLogistics",
  "healthcare",
  "education",
  "legal",
  "tradesTechnical",
  "other",
];

/** Mirrors the app's ResumeMarket cases. */
export const BENCHMARK_MARKETS = [
  "southAfrica",
  "unitedKingdom",
  "unitedStates",
  "europeanUnion",
  "australia",
  "canada",
  "international",
];

export const BENCHMARK_SENIORITIES = ["entry", "mid", "senior", "lead"];

/** Distinct installations required before a cohort may be shown to anyone. */
export const BENCHMARK_MIN_CONTRIBUTORS = 8;
/** Applications required on top of the contributor floor, so eight people who
 * have each applied twice do not become a published statistic. */
export const BENCHMARK_MIN_APPLICATIONS = 30;
/** No single installation may count for more than this many settled
 * applications, so one heavy user cannot define a small cohort. */
export const BENCHMARK_MAX_WEIGHTED_SETTLED = 40;
/** Upper bounds on a single contribution, to reject nonsense outright. */
export const BENCHMARK_MAX_SETTLED = 2000;
export const BENCHMARK_MAX_DAYS_TO_PROGRESS = 180;

/**
 * Normalises a cohort to its canonical key, or null when any dimension is not
 * on the allow-list. There is no free-text path into a cohort.
 */
export function benchmarkCohortKey(value) {
  if (!value || typeof value !== "object") return null;
  const family = BENCHMARK_ROLE_FAMILIES.includes(value.roleFamily) ? value.roleFamily : null;
  const market = BENCHMARK_MARKETS.includes(value.market) ? value.market : null;
  const seniority = BENCHMARK_SENIORITIES.includes(value.seniority) ? value.seniority : null;
  if (!family || !market || !seniority) return null;
  return `${family}:${market}:${seniority}`;
}

function wholeNumber(value, max) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  const rounded = Math.round(parsed);
  if (rounded < 0 || rounded > max) return null;
  return rounded;
}

/**
 * Sanitises one installation's contribution. Returns null when the cohort or the
 * counts are unusable, so a caller can reject without interpreting anything.
 *
 * `weightedSettled` is what the aggregate should actually add: a contribution is
 * capped so that a single prolific user cannot dominate a thin cohort, and the
 * progressed count is scaled with it so the ratio survives the cap.
 */
export function benchmarkContribution(value) {
  if (!value || typeof value !== "object") return null;
  const cohort = benchmarkCohortKey(value.cohort);
  if (!cohort) return null;

  const settled = wholeNumber(value.settled, BENCHMARK_MAX_SETTLED);
  if (settled === null || settled < 1) return null;

  const progressed = wholeNumber(value.progressed, BENCHMARK_MAX_SETTLED);
  if (progressed === null || progressed > settled) return null;

  // An out-of-range or absent timing is dropped rather than failing the whole
  // contribution — the progression counts are still worth having.
  const medianDaysToProgress =
    value.medianDaysToProgress === null || value.medianDaysToProgress === undefined
      ? null
      : wholeNumber(value.medianDaysToProgress, BENCHMARK_MAX_DAYS_TO_PROGRESS);

  const weightedSettled = Math.min(settled, BENCHMARK_MAX_WEIGHTED_SETTLED);
  const weightedProgressed =
    weightedSettled === settled
      ? progressed
      : Math.round((progressed / settled) * weightedSettled);

  return { cohort, settled, progressed, medianDaysToProgress, weightedSettled, weightedProgressed };
}

/**
 * Decides whether an accumulated cohort may be published, and rounds what is
 * released. Rounding is not cosmetic: unrounded rates over a known contributor
 * count make it easier to reason backwards toward one person's history.
 */
export function benchmarkRelease(aggregate) {
  const contributors = Number(aggregate?.contributors) || 0;
  const settled = Number(aggregate?.settled) || 0;
  const progressed = Number(aggregate?.progressed) || 0;
  const daysToProgressTotal = Number(aggregate?.daysToProgressTotal) || 0;
  const daysToProgressContributors = Number(aggregate?.daysToProgressContributors) || 0;

  if (
    contributors < BENCHMARK_MIN_CONTRIBUTORS ||
    settled < BENCHMARK_MIN_APPLICATIONS ||
    progressed > settled
  ) {
    return { released: false, contributors, settled };
  }

  return {
    released: true,
    contributors,
    settled,
    progressionPercent: Math.round((progressed / settled) * 100),
    // Only released once enough contributors reported a timing at all.
    medianDaysToProgress:
      daysToProgressContributors >= BENCHMARK_MIN_CONTRIBUTORS
        ? Math.round(daysToProgressTotal / daysToProgressContributors)
        : null,
  };
}
