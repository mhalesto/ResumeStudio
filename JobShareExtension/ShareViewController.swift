import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  fileprivate let appGroupID = "group.com.halalisanimbanjwa.ResumeStudio"
  /// Must match `SharedJobInbox` in the app, which drains this same file.
  fileprivate let queueFileName = "pending-job-captures.json"
  fileprivate let queueLimit = 20

  override func viewDidLoad() {
    super.viewDidLoad()
    installConfirmation()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await captureAndOpenApp() }
  }

  /// A share extension that reads the page and closes shows nothing at all, and
  /// opening the app afterwards is not something an extension can count on. Left
  /// as it was, a share that worked perfectly looked identical to one that did
  /// nothing. This says it landed, whether or not the app comes forward.
  private func installConfirmation() {
    view.backgroundColor = .clear

    let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    panel.layer.cornerRadius = 22
    panel.layer.cornerCurve = .continuous
    panel.clipsToBounds = true
    panel.translatesAutoresizingMaskIntoConstraints = false

    let tick = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    tick.contentMode = .scaleAspectFit
    tick.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
      pointSize: 34, weight: .semibold)
    tick.tintColor = .systemGreen

    let caption = UILabel()
    caption.text = NSLocalizedString(
      "Saved to ResumeStudio", comment: "Confirmation after sharing a job page")
    caption.font = .preferredFont(forTextStyle: .headline)
    caption.adjustsFontForContentSizeCategory = true
    caption.textAlignment = .center

    let stack = UIStackView(arrangedSubviews: [tick, caption])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 11
    stack.translatesAutoresizingMaskIntoConstraints = false

    panel.contentView.addSubview(stack)
    view.addSubview(panel)

    NSLayoutConstraint.activate([
      panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      panel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 26),
      stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -26),
      stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 30),
      stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -30),
    ])
  }

  private func captureAndOpenApp() async {
    var sharedURL = ""
    var sharedText = ""
    var sharedTitle = ""
    var sharedPosting = ""

    for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
      for attachment in item.attachments ?? [] {
        // Safari runs CapturePage.js in the shared page and returns what it read
        // as a property list. This is the only path that sees a posting behind a
        // sign-in, so it is preferred over everything else on the item.
        if attachment.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
          let value = try? await attachment.loadItem(
            forTypeIdentifier: UTType.propertyList.identifier),
          let container = value as? [String: Any],
          let results = container[NSExtensionJavaScriptPreprocessingResultsKey]
            as? [String: Any]
        {
          sharedURL = (results["url"] as? String)?.nilIfEmpty ?? sharedURL
          sharedTitle = (results["title"] as? String)?.nilIfEmpty ?? sharedTitle
          sharedPosting = (results["posting"] as? String)?.nilIfEmpty ?? sharedPosting
          sharedText = (results["text"] as? String)?.nilIfEmpty ?? sharedText
        }
        if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier),
          let value = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier)
        {
          let url = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
          if sharedURL.isEmpty { sharedURL = url }
        }
        // A selection the reader made by hand is a deliberate answer to "this
        // part", so it wins over the whole page the script swept up.
        if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
          let value = try? await attachment.loadItem(
            forTypeIdentifier: UTType.plainText.identifier),
          let selected = (value as? String)?.nilIfEmpty
        {
          sharedText = selected
        }
      }
    }

    enqueue(
      SharedCapture(
        url: sharedURL, text: sharedText, title: sharedTitle, posting: sharedPosting,
        receivedAt: Date()))

    // Long enough to be read, short enough not to be in the way.
    try? await Task.sleep(for: .milliseconds(650))
    if let url = URL(string: "resumestudio://capture-job") {
      _ = await extensionContext?.open(url)
    }
    extensionContext?.completeRequest(returningItems: nil)
  }
}

extension ShareViewController {
  /// Appends to the queue the app drains, rather than replacing what is there.
  /// Working through a board means sharing several roles in a row, and the app
  /// is usually not opened until well after the last of them.
  ///
  /// The app writes this same file as it drains, so read, append, write back is
  /// done inside a coordinated write. Without it a share landing while the app
  /// took one from the front could overwrite that change, or be overwritten by
  /// it — the queue is the one piece of state two processes both mutate.
  ///
  /// This deliberately mirrors `SharedJobInbox` in the app rather than sharing
  /// code with it: an extension carries its own copy of everything it links,
  /// and the queue's shape is four fields and a cap. Both sides must agree on
  /// the file name, the field names and the cap.
  fileprivate func enqueue(_ capture: SharedCapture) {
    guard
      let url = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
        .appendingPathComponent(queueFileName)
    else { return }

    var coordinatorError: NSError?
    NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinatorError) {
      url in
      var queued: [SharedCapture] = []
      if let data = try? Data(contentsOf: url),
        let decoded = try? JSONDecoder().decode([SharedCapture].self, from: data)
      {
        queued = decoded
      }
      queued.append(capture)
      queued.sort { $0.receivedAt < $1.receivedAt }
      if let data = try? JSONEncoder().encode(queued.suffix(queueLimit)) {
        try? data.write(
          to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      }
    }
  }
}

struct SharedCapture: Codable {
  var url: String
  var text: String
  var title: String
  var posting: String
  var receivedAt: Date
}

extension String {
  fileprivate var nilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
