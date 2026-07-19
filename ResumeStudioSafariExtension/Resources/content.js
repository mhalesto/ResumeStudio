const profileFieldRules = [
  { keys: ["first_name", "firstname", "given_name"], value: profile => profile.fullName?.trim().split(/\s+/)[0] },
  { keys: ["last_name", "lastname", "family_name", "surname"], value: profile => profile.fullName?.trim().split(/\s+/).slice(1).join(" ") },
  { keys: ["full_name", "fullname", "name"], value: profile => profile.fullName },
  { keys: ["email", "email_address"], value: profile => profile.email },
  { keys: ["phone", "telephone", "mobile"], value: profile => profile.phone },
  { keys: ["headline", "job_title", "current_title"], value: profile => profile.headline },
  { keys: ["summary", "profile", "about", "cover_note"], value: profile => profile.professionalProfile },
  { keys: ["skills", "competencies"], value: profile => Array.isArray(profile.skills) ? profile.skills.join(", ") : "" }
];

const answerFieldSelector = [
  "input:not([type='hidden']):not([type='file']):not([type='password'])",
  "textarea",
  "select"
].join(",");

function normalize(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function fieldIdentity(field) {
  return normalize([
    field.name,
    field.id,
    field.autocomplete,
    field.placeholder,
    field.getAttribute("aria-label")
  ].filter(Boolean).join(" ")).replace(/\s+/g, "_");
}

function labelledText(field) {
  const pieces = [];
  field.labels?.forEach(label => pieces.push(label.innerText || label.textContent));

  const enclosingLabel = field.closest("label");
  if (enclosingLabel) pieces.push(enclosingLabel.innerText || enclosingLabel.textContent);

  const fieldset = field.closest("fieldset");
  const legend = fieldset?.querySelector(":scope > legend");
  if (legend) pieces.push(legend.innerText || legend.textContent);

  const labelledBy = field.getAttribute("aria-labelledby");
  if (labelledBy) {
    labelledBy.split(/\s+/).forEach(id => {
      const label = document.getElementById(id);
      if (label) pieces.push(label.innerText || label.textContent);
    });
  }

  const previous = field.previousElementSibling;
  if (previous && ["LABEL", "LEGEND", "P", "SPAN"].includes(previous.tagName)) {
    pieces.push(previous.innerText || previous.textContent);
  }

  pieces.push(
    field.getAttribute("aria-label"),
    field.placeholder,
    field.name,
    field.id
  );

  return normalize(pieces.filter(Boolean).join(" "));
}

function setNativeValue(field, value) {
  const prototype = field instanceof HTMLTextAreaElement
    ? HTMLTextAreaElement.prototype
    : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
  setter ? setter.call(field, value) : (field.value = value);
  field.dispatchEvent(new Event("input", { bubbles: true }));
  field.dispatchEvent(new Event("change", { bubbles: true }));
  return true;
}

function fillProfileField(field, value) {
  if (!value || field.value?.trim()) return false;
  if (!(field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement)) return false;
  if (["radio", "checkbox"].includes(field.type)) return false;
  return setNativeValue(field, value);
}

function fillProfile(profile) {
  let filled = 0;
  document.querySelectorAll("input:not([type='hidden']):not([type='file']), textarea").forEach(field => {
    const identity = fieldIdentity(field);
    const rule = profileFieldRules.find(candidate => candidate.keys.some(key =>
      identity === key || identity.startsWith(`${key}_`) || identity.endsWith(`_${key}`) || identity.includes(`_${key}_`)
    ));
    if (rule && fillProfileField(field, rule.value(profile))) filled += 1;
  });
  return filled;
}

function radioGroup(field) {
  if (!field.name) return [field];
  return Array.from(document.querySelectorAll("input[type='radio']"))
    .filter(candidate => candidate.name === field.name && candidate.form === field.form);
}

function answerFieldDescriptors() {
  const descriptors = [];
  const visitedRadioGroups = new Set();

  document.querySelectorAll(answerFieldSelector).forEach(field => {
    if (field.disabled || field.readOnly) return;
    if (field instanceof HTMLInputElement && field.type === "radio") {
      const key = `${field.form?.id || "page"}:${field.name || field.id}`;
      if (visitedRadioGroups.has(key)) return;
      visitedRadioGroups.add(key);
      const controls = radioGroup(field);
      descriptors.push({ type: "radio", controls, question: labelledText(field) });
      return;
    }
    if (field instanceof HTMLInputElement && field.type === "checkbox") {
      descriptors.push({ type: "checkbox", controls: [field], question: labelledText(field) });
      return;
    }
    descriptors.push({
      type: field instanceof HTMLSelectElement ? "select" : "text",
      controls: [field],
      question: labelledText(field)
    });
  });
  return descriptors;
}

function matchScore(question, savedAnswer) {
  if (!question || !Array.isArray(savedAnswer.matchTerms)) return 0;
  return savedAnswer.matchTerms.reduce((best, term) => {
    const normalizedTerm = normalize(term);
    if (normalizedTerm.length < 3 || !question.includes(normalizedTerm)) return best;
    return Math.max(best, normalizedTerm.length);
  }, 0);
}

function bestSavedAnswer(question, savedAnswers) {
  return savedAnswers
    .map(answer => ({ answer, score: matchScore(normalize(question), answer) }))
    .filter(candidate => candidate.score > 0)
    .sort((left, right) => right.score - left.score)[0]?.answer || null;
}

function suggestedAnswers(savedAnswers) {
  const validAnswers = savedAnswers.filter(item =>
    item && typeof item.answer === "string" && item.answer.trim()
      && Array.isArray(item.matchTerms) && item.matchTerms.length
  );

  return answerFieldDescriptors().reduce((suggestions, descriptor) => {
    const savedAnswer = bestSavedAnswer(descriptor.question, validAnswers);
    if (savedAnswer) suggestions.push({ descriptor, savedAnswer });
    return suggestions;
  }, []);
}

function optionLabel(control) {
  return normalize(control.labels?.[0]?.innerText || control.parentElement?.innerText || control.value);
}

function fillSuggestedAnswer(suggestion) {
  const { descriptor, savedAnswer } = suggestion;
  const answer = savedAnswer.answer.trim();
  const normalizedAnswer = normalize(answer);

  if (descriptor.type === "text") {
    const field = descriptor.controls[0];
    if (field.value?.trim()) return false;
    return setNativeValue(field, answer);
  }

  if (descriptor.type === "select") {
    const select = descriptor.controls[0];
    const option = Array.from(select.options).find(candidate => {
      const label = normalize(candidate.textContent);
      const value = normalize(candidate.value);
      return label === normalizedAnswer || value === normalizedAnswer
        || (normalizedAnswer.length > 1 && (label.includes(normalizedAnswer) || normalizedAnswer.includes(label)));
    });
    if (!option) return false;
    select.value = option.value;
    select.dispatchEvent(new Event("input", { bubbles: true }));
    select.dispatchEvent(new Event("change", { bubbles: true }));
    return true;
  }

  if (descriptor.type === "radio") {
    const radio = descriptor.controls.find(control => {
      const label = optionLabel(control);
      return label === normalizedAnswer || normalize(control.value) === normalizedAnswer
        || (normalizedAnswer.length > 1 && (label.includes(normalizedAnswer) || normalizedAnswer.includes(label)));
    });
    if (!radio) return false;
    radio.click();
    return true;
  }

  if (descriptor.type === "checkbox") {
    const checkbox = descriptor.controls[0];
    const yes = ["yes", "true", "agree", "i agree"].includes(normalizedAnswer);
    const no = ["no", "false", "disagree", "i disagree"].includes(normalizedAnswer);
    if (!yes && !no) return false;
    const desired = yes;
    if (checkbox.checked !== desired) checkbox.click();
    return true;
  }

  return false;
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

function showAnswerPanel(suggestions, profileFilled) {
  document.getElementById("resume-studio-answer-panel")?.remove();
  const host = document.createElement("div");
  host.id = "resume-studio-answer-panel";
  Object.assign(host.style, {
    position: "fixed", right: "18px", bottom: "18px", zIndex: "2147483647"
  });
  const shadow = host.attachShadow({ mode: "closed" });
  const style = document.createElement("style");
  style.textContent = `
    * { box-sizing: border-box; }
    .panel { width: min(390px, calc(100vw - 36px)); max-height: min(620px, calc(100vh - 36px)); overflow: auto;
      color: #f5f5f7; background: #1c1c1e; border: 1px solid #3a3a3c; border-radius: 18px;
      box-shadow: 0 16px 48px rgba(0,0,0,.42); font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
    header { position: sticky; top: 0; display: flex; align-items: center; gap: 10px; padding: 15px 16px;
      background: rgba(28,28,30,.97); border-bottom: 1px solid #3a3a3c; }
    h2 { flex: 1; margin: 0; font-size: 17px; } .close { background: transparent; color: #aaa; border: 0; font-size: 22px; cursor: pointer; }
    .summary { margin: 0; padding: 12px 16px; color: #b5b5b8; line-height: 1.4; }
    .answers { padding: 0 12px 12px; } .item { padding: 12px; margin: 0 0 9px; background: #2c2c2e; border-radius: 13px; }
    .question { margin: 0 0 5px; color: #ff6a22; font-weight: 700; } .answer { margin: 0 0 10px; line-height: 1.35; white-space: pre-wrap; }
    button.fill, button.fillAll { border: 0; border-radius: 9px; padding: 8px 12px; background: #c9470d; color: white; font-weight: 700; cursor: pointer; }
    button.fill:disabled { background: #3f7f4c; cursor: default; } button.fillAll { width: calc(100% - 24px); margin: 0 12px 12px; }
    .privacy { margin: 0; padding: 0 16px 16px; color: #8e8e93; font-size: 12px; line-height: 1.35; }
  `;
  shadow.appendChild(style);

  const panel = document.createElement("section");
  panel.className = "panel";
  const header = document.createElement("header");
  const title = document.createElement("h2");
  title.textContent = "Resume Studio answers";
  const close = document.createElement("button");
  close.className = "close";
  close.type = "button";
  close.setAttribute("aria-label", "Close Resume Studio suggestions");
  close.textContent = "×";
  close.addEventListener("click", () => host.remove());
  header.append(title, close);
  panel.appendChild(header);

  const summary = document.createElement("p");
  summary.className = "summary";
  summary.textContent = `${profileFilled} profile field${profileFilled === 1 ? "" : "s"} filled. ${suggestions.length} saved answer suggestion${suggestions.length === 1 ? "" : "s"} found.`;
  panel.appendChild(summary);

  if (suggestions.length) {
    const answers = document.createElement("div");
    answers.className = "answers";
    suggestions.forEach(suggestion => {
      const item = document.createElement("article");
      item.className = "item";
      const question = document.createElement("p");
      question.className = "question";
      question.textContent = suggestion.savedAnswer.title || "Matched application question";
      const answer = document.createElement("p");
      answer.className = "answer";
      answer.textContent = suggestion.savedAnswer.answer;
      const fill = document.createElement("button");
      fill.className = "fill";
      fill.type = "button";
      fill.textContent = "Fill this answer";
      fill.addEventListener("click", () => {
        const didFill = fillSuggestedAnswer(suggestion);
        fill.textContent = didFill ? "Filled" : "Could not match this field type";
        fill.disabled = didFill;
      });
      item.append(question, answer, fill);
      answers.appendChild(item);
      suggestion.button = fill;
    });
    panel.appendChild(answers);

    const fillAll = document.createElement("button");
    fillAll.className = "fillAll";
    fillAll.type = "button";
    fillAll.textContent = "Fill all suggestions";
    fillAll.addEventListener("click", () => {
      let filled = 0;
      suggestions.forEach(suggestion => {
        if (fillSuggestedAnswer(suggestion)) {
          filled += 1;
          suggestion.button.textContent = "Filled";
          suggestion.button.disabled = true;
        }
      });
      fillAll.textContent = `${filled} answer${filled === 1 ? "" : "s"} filled — review before submitting`;
      fillAll.disabled = true;
    });
    panel.appendChild(fillAll);
  }

  const privacy = document.createElement("p");
  privacy.className = "privacy";
  privacy.textContent = "Nothing is submitted automatically. Review every field before continuing.";
  panel.appendChild(privacy);
  shadow.appendChild(panel);
  document.documentElement.appendChild(host);
}

if (typeof browser !== "undefined" && browser.runtime?.onMessage) {
  browser.runtime.onMessage.addListener(message => {
    if (message?.type === "resumeStudioNotice") {
      showNotice(message.message);
      return;
    }
    if (message?.type !== "resumeStudioAutofill" || !message.profile) return;

    const profileFilled = fillProfile(message.profile);
    const answers = Array.isArray(message.answers) ? message.answers : [];
    if (answers.length) {
      showAnswerPanel(suggestedAnswers(answers), profileFilled);
    } else {
      showNotice(`Resume Studio filled ${profileFilled} profile field${profileFilled === 1 ? "" : "s"}. Add and publish answers in the app for screening-question suggestions.`);
    }
    console.info(`Resume Studio filled ${profileFilled} profile field${profileFilled === 1 ? "" : "s"}. Review everything before submitting.`);
  });
}

if (typeof module !== "undefined") {
  module.exports = { normalize, matchScore, bestSavedAnswer };
}
