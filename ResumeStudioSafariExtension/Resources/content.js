const fieldRules = [
  { keys: ["first_name", "firstname", "given-name"], value: profile => profile.fullName?.trim().split(/\s+/)[0] },
  { keys: ["last_name", "lastname", "family-name", "surname"], value: profile => profile.fullName?.trim().split(/\s+/).slice(1).join(" ") },
  { keys: ["full_name", "fullname", "name"], value: profile => profile.fullName },
  { keys: ["email", "email_address"], value: profile => profile.email },
  { keys: ["phone", "telephone", "mobile"], value: profile => profile.phone },
  { keys: ["headline", "job_title", "current_title"], value: profile => profile.headline },
  { keys: ["summary", "profile", "about", "cover_note"], value: profile => profile.professionalProfile },
  { keys: ["skills", "competencies"], value: profile => Array.isArray(profile.skills) ? profile.skills.join(", ") : "" }
];

function fieldIdentity(field) {
  return [field.name, field.id, field.autocomplete, field.placeholder, field.getAttribute("aria-label")]
    .filter(Boolean)
    .join(" ")
    .toLowerCase()
    .replace(/[\s-]+/g, "_");
}

function fillField(field, value) {
  if (!value || field.value?.trim()) return false;
  const prototype = field instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
  setter ? setter.call(field, value) : (field.value = value);
  field.dispatchEvent(new Event("input", { bubbles: true }));
  field.dispatchEvent(new Event("change", { bubbles: true }));
  return true;
}

function showNotice(message) {
  document.getElementById("resume-studio-notice")?.remove();
  const notice = document.createElement("div");
  notice.id = "resume-studio-notice";
  notice.textContent = message;
  Object.assign(notice.style, {
    position: "fixed", right: "18px", bottom: "18px", zIndex: "2147483647",
    maxWidth: "340px", padding: "12px 16px", borderRadius: "12px",
    color: "white", background: "#C9470D", font: "600 14px -apple-system, sans-serif",
    boxShadow: "0 8px 28px rgba(0,0,0,.28)"
  });
  document.documentElement.appendChild(notice);
  setTimeout(() => notice.remove(), 5000);
}

browser.runtime.onMessage.addListener((message) => {
  if (message?.type === "resumeStudioNotice") {
    showNotice(message.message);
    return;
  }
  if (message?.type !== "resumeStudioAutofill" || !message.profile) return;
  let filled = 0;
  document.querySelectorAll("input:not([type='hidden']):not([type='file']), textarea").forEach(field => {
    const identity = fieldIdentity(field);
    const rule = fieldRules.find(candidate => candidate.keys.some(key =>
      identity === key || identity.startsWith(`${key}_`) || identity.endsWith(`_${key}`) || identity.includes(`_${key}_`)
    ));
    if (rule && fillField(field, rule.value(message.profile))) filled += 1;
  });
  showNotice(`Resume Studio filled ${filled} field${filled === 1 ? "" : "s"}. Review everything before submitting.`);
  console.info(`Resume Studio filled ${filled} field${filled === 1 ? "" : "s"}. Review everything before submitting.`);
});
