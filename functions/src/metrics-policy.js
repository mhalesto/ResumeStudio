export const productInsightEvents = new Set([
  "onboarding_goal_selected",
  "document_exported",
  "job_captured",
  "ai_completed",
  "plans_presented",
  "feedback_opened",
]);

export function productInsightPayload(value) {
  if (!value || typeof value !== "object") return null;
  const event = String(value.event || "");
  const plan = ["free", "go", "pro"].includes(value.plan) ? value.plan : "free";
  const source = ["app", "server_ai", "on_device_ai"].includes(value.source)
    ? value.source : "app";
  const version = String(value.appVersion || "unknown")
    .replace(/\./g, "_")
    .replace(/[^A-Za-z0-9_-]/g, "")
    .slice(0, 24) || "unknown";
  if (!productInsightEvents.has(event)) return null;
  const goal = ["build", "tailor", "organize"].includes(value.goal) ? value.goal : null;
  return { event, plan, source, version, goal };
}
