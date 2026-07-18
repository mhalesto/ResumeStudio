import test from "node:test";
import assert from "node:assert/strict";
import { productInsightPayload } from "../src/metrics-policy.js";

test("product insights accept only coarse allow-listed fields", () => {
  assert.deepEqual(productInsightPayload({
    event: "document_exported", plan: "pro", source: "app", appVersion: "1.0-14",
    resumeText: "must never be retained", company: "Private employer",
  }), {
    event: "document_exported", plan: "pro", source: "app", version: "1_0-14", goal: null,
  });
});

test("product insights reject unknown events and normalize dimensions", () => {
  assert.equal(productInsightPayload({ event: "resume_contents" }), null);
  assert.deepEqual(productInsightPayload({
    event: "ai_completed", plan: "enterprise", source: "mystery", appVersion: "1.0 <script>",
  }), {
    event: "ai_completed", plan: "free", source: "app", version: "1_0script", goal: null,
  });
});

test("product insights keep only allow-listed onboarding goals", () => {
  assert.equal(productInsightPayload({ event: "onboarding_goal_selected", goal: "tailor" }).goal, "tailor");
  assert.equal(productInsightPayload({ event: "onboarding_goal_selected", goal: "private data" }).goal, null);
});
