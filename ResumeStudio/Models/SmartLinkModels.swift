import Foundation

/// A hosted, trackable résumé link: sent to a recruiter instead of an
/// attachment, and reporting back when it is opened and for how long it is
/// read. The counterpart of the ATS score and the Recruiter Scan — this one
/// tells you what happened *after* you pressed send.
struct SmartLink: Identifiable, Codable, Equatable {
  var id = UUID()
  /// The capability: whoever holds the token holds the link. Generated on
  /// device, never derived from the résumé or the person.
  var token: String
  var url: URL
  var title: String
  /// Who it was sent to — a label for the user, never shown to the viewer
  /// unless they chose to put it on the page.
  var company: String
  var createdAt: Date
  var expiresAt: Date
  var status: SmartLinkStatus = .open
  /// The last activity feed fetched from the backend.
  var views: [SmartLinkView] = []
  var lastRefreshedAt: Date?
  /// How many opens the user has been told about (notification + badge),
  /// so only genuinely new activity alerts.
  var acknowledgedOpens: Int = 0

  var totalOpens: Int { views.reduce(0) { $0 + $1.opens } }
  var totalSeconds: Int { views.reduce(0) { $0 + $1.seconds } }
  var lastSeenAt: Date? { views.compactMap(\.lastSeenAt).max() }
  var unseenOpens: Int { max(0, totalOpens - acknowledgedOpens) }
  var isActive: Bool { status == .open && expiresAt > Date() }
}

enum SmartLinkStatus: String, Codable {
  case open
  case revoked
  case expired

  var title: String {
    switch self {
    case .open: "Live"
    case .revoked: "Revoked"
    case .expired: "Expired"
    }
  }
}

/// One visitor's reading of the résumé, as coarse as the backend records it:
/// a device hint, opens, and honest seconds — never identity.
struct SmartLinkView: Identifiable, Codable, Equatable {
  var id: String
  var firstOpenedAt: Date?
  var lastSeenAt: Date?
  var opens: Int
  var seconds: Int
  var viewer: String
  var downloadedPDF: Bool
}

extension SmartLink {
  /// A fresh capability token in the backend's accepted alphabet.
  static func newToken() -> String {
    let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
    return String((0..<40).compactMap { _ in alphabet.randomElement() })
  }
}
