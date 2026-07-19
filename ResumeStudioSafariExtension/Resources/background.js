browser.action.onClicked.addListener(async (tab) => {
  try {
    const response = await browser.runtime.sendNativeMessage(
      "com.halalisanimbanjwa.ResumeStudio",
      { command: "autofillProfile" }
    );
    if (!response?.ok) {
      await browser.tabs.sendMessage(tab.id, {
        type: "resumeStudioNotice",
        message: response?.message || "Resume Studio profile is unavailable."
      });
      return;
    }
    await browser.tabs.sendMessage(tab.id, {
      type: "resumeStudioAutofill",
      profile: response.profile,
      answers: response.answers || []
    });
  } catch (error) {
    console.error("Resume Studio autofill failed", error);
    if (tab?.id) {
      await browser.tabs.sendMessage(tab.id, {
        type: "resumeStudioNotice",
        message: "Resume Studio could not fill this page. Open the app and refresh your Safari profile."
      }).catch(() => {});
    }
  }
});
