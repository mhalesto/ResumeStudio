import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  private let appGroup = "group.com.halalisanimbanjwa.ResumeStudio"

  func beginRequest(with context: NSExtensionContext) {
    let response = NSExtensionItem()
    let defaults = UserDefaults(suiteName: appGroup)
    let data = defaults?.data(forKey: "safariAutofillProfile")
    let profile = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

    response.userInfo = [
      SFExtensionMessageKey: [
        "ok": profile != nil,
        "profile": profile ?? [:],
        "message": profile == nil
          ? "Open Resume Studio and publish your private Safari profile first."
          : "Profile ready",
      ]
    ]
    context.completeRequest(returningItems: [response])
  }
}
