import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let appGroupID = "group.com.halalisanimbanjwa.ResumeStudio"
  private let pendingKey = "pendingJobCapture"

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await captureAndOpenApp() }
  }

  private func captureAndOpenApp() async {
    var sharedURL = ""
    var sharedText = ""

    for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
      for attachment in item.attachments ?? [] {
        if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier),
          let value = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier)
        {
          sharedURL = (value as? URL)?.absoluteString ?? (value as? String) ?? sharedURL
        }
        if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
          let value = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier)
        {
          sharedText = (value as? String) ?? sharedText
        }
      }
    }

    let payload = SharedCapture(url: sharedURL, text: sharedText, receivedAt: Date())
    if let data = try? JSONEncoder().encode(payload) {
      UserDefaults(suiteName: appGroupID)?.set(data, forKey: pendingKey)
    }

    if let url = URL(string: "resumestudio://capture-job") {
      _ = await extensionContext?.open(url)
    }
    extensionContext?.completeRequest(returningItems: nil)
  }
}

private struct SharedCapture: Codable {
  var url: String
  var text: String
  var receivedAt: Date
}
