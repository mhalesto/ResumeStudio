import test from "node:test";
import assert from "node:assert/strict";
import {
  BENCHMARK_MAX_WEIGHTED_SETTLED,
  BENCHMARK_MIN_APPLICATIONS,
  BENCHMARK_MIN_CONTRIBUTORS,
  benchmarkCohortKey,
  benchmarkContribution,
  benchmarkRelease,
} from "../src/benchmark-policy.js";

test("a cohort accepts only allow-listed dimensions", () => {
  assert.equal(
    benchmarkCohortKey({ roleFamily: "design", market: "southAfrica", seniority: "mid" }),
    "design:southAfrica:mid",
  );
  // No free-text path into a cohort, in any dimension.
  assert.equal(
    benchmarkCohortKey({ roleFamily: "Senior Widget Wrangler", market: "southAfrica", seniority: "mid" }),
    null,
  );
  assert.equal(
    benchmarkCohortKey({ roleFamily: "design", market: "narnia", seniority: "mid" }),
    null,
  );
  assert.equal(benchmarkCohortKey({ roleFamily: "design", market: "southAfrica" }), null);
  assert.equal(benchmarkCohortKey(null), null);
});

test("a contribution carries counts only and drops everything else", () => {
  const contribution = benchmarkContribution({
    cohort: { roleFamily: "engineering", market: "unitedKingdom", seniority: "senior" },
    settled: 10,
    progressed: 3,
    medianDaysToProgress: 9,
    company: "Private employer",
    resumeText: "must never be retained",
    email: "someone@example.com",
  });
  assert.deepEqual(contribution, {
    cohort: "engineering:unitedKingdom:senior",
    settled: 10,
    progressed: 3,
    medianDaysToProgress: 9,
    weightedSettled: 10,
    weightedProgressed: 3,
  });
});

test("a contribution is rejected when the counts cannot be true", () => {
  const cohort = { roleFamily: "sales", market: "canada", seniority: "entry" };
  // More interviews than applications.
  assert.equal(benchmarkContribution({ cohort, settled: 4, progressed: 9 }), null);
  assert.equal(benchmarkContribution({ cohort, settled: 0, progressed: 0 }), null);
  assert.equal(benchmarkContribution({ cohort, settled: -3, progressed: 0 }), null);
  assert.equal(benchmarkContribution({ cohort, settled: 5e9, progressed: 1 }), null);
  assert.equal(benchmarkContribution({ cohort: { roleFamily: "sales" }, settled: 4, progressed: 1 }), null);
});

test("one prolific installation cannot define a thin cohort", () => {
  const contribution = benchmarkContribution({
    cohort: { roleFamily: "marketing", market: "australia", seniority: "mid" },
    settled: 400,
    progressed: 200,
    medianDaysToProgress: 12,
  });
  assert.equal(contribution.settled, 400);
  assert.equal(contribution.weightedSettled, BENCHMARK_MAX_WEIGHTED_SETTLED);
  // The cap preserves the ratio rather than truncating the numerator.
  assert.equal(contribution.weightedProgressed, BENCHMARK_MAX_WEIGHTED_SETTLED / 2);
});

test("an out-of-range timing is dropped without losing the contribution", () => {
  const contribution = benchmarkContribution({
    cohort: { roleFamily: "legal", market: "international", seniority: "lead" },
    settled: 6,
    progressed: 2,
    medianDaysToProgress: 5000,
  });
  assert.equal(contribution.medianDaysToProgress, null);
  assert.equal(contribution.progressed, 2);
});

test("a cohort stays unpublished until enough distinct people are in it", () => {
  const belowContributors = benchmarkRelease({
    contributors: BENCHMARK_MIN_CONTRIBUTORS - 1,
    settled: 200,
    progressed: 40,
  });
  assert.equal(belowContributors.released, false);
  assert.equal(belowContributors.progressionPercent, undefined);

  // Enough people, but between them too little history to be a statistic.
  const belowVolume = benchmarkRelease({
    contributors: BENCHMARK_MIN_CONTRIBUTORS,
    settled: BENCHMARK_MIN_APPLICATIONS - 1,
    progressed: 4,
  });
  assert.equal(belowVolume.released, false);
});

test("a released cohort is rounded, never raw", () => {
  const released = benchmarkRelease({
    contributors: 12,
    settled: 97,
    progressed: 31,
    daysToProgressTotal: 121,
    daysToProgressContributors: 12,
  });
  assert.equal(released.released, true);
  // 31/97 is 31.9587...%, published as a whole number.
  assert.equal(released.progressionPercent, 32);
  assert.equal(released.medianDaysToProgress, 10);
  assert.equal(released.contributors, 12);
});

test("a timing needs its own contributor floor", () => {
  const released = benchmarkRelease({
    contributors: 20,
    settled: 150,
    progressed: 30,
    daysToProgressTotal: 30,
    daysToProgressContributors: BENCHMARK_MIN_CONTRIBUTORS - 1,
  });
  assert.equal(released.released, true);
  assert.equal(released.progressionPercent, 20);
  // The progression rate clears the bar; the timing does not.
  assert.equal(released.medianDaysToProgress, null);
});
