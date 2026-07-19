const assert = require("node:assert/strict");
const test = require("node:test");
const {
  normalize,
  matchScore,
  bestSavedAnswer
} = require("../../ResumeStudioSafariExtension/Resources/content.js");

const answers = [
  {
    title: "Work authorization",
    answer: "Yes",
    matchTerms: ["authorized to work", "right to work"]
  },
  {
    title: "Availability",
    answer: "Four weeks",
    matchTerms: ["notice period", "available to start"]
  },
  {
    title: "Custom portfolio question",
    answer: "https://example.invalid/work",
    matchTerms: ["portfolio website"]
  }
];

test("normalizes application labels without relying on punctuation", () => {
  assert.equal(normalize("When can you START?"), "when can you start");
});

test("scores only configured matching phrases", () => {
  assert.ok(matchScore("what is your notice period", answers[1]) > 0);
  assert.equal(matchScore("what is your favourite colour", answers[1]), 0);
});

test("selects the best saved answer for a screening question", () => {
  assert.equal(
    bestSavedAnswer("Are you legally AUTHORIZED to work in this country?", answers)?.answer,
    "Yes"
  );
  assert.equal(bestSavedAnswer("Tell us about a difficult project", answers), null);
});
