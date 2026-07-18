import Foundation

/// A hosted, trackable résumé link: sent to a recruiter instead of an
/// attachment, and reporting back when it is opened and for how long it is
/// read. The counterpart of the ATS score and the Recruiter Scan — this one
/// tells you what happened *after* you pressed send.
struct SmartLink: Identifiable, Codable, Equatable {
  var id = UUID()
  /// Stable backend document identifier used to recover and manage a link
  /// when the app's local capability token is no longer available.
  var remoteID: String? = nil
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
  /// Privacy-safe day totals from the backend. Optional keeps links persisted
  /// by older app versions decodable; use `dailyActivity` everywhere else.
  var activityByDay: [SmartLinkDailyActivity]? = nil
  var lastRefreshedAt: Date?
  /// How many opens the user has been told about (notification + badge),
  /// so only genuinely new activity alerts.
  var acknowledgedOpens: Int = 0

  var totalOpens: Int { views.reduce(0) { $0 + $1.opens } }
  var totalSeconds: Int { views.reduce(0) { $0 + $1.seconds } }
  var totalDownloads: Int { views.count(where: \.downloadedPDF) }
  var dailyActivity: [SmartLinkDailyActivity] { activityByDay ?? [] }
  var lastSeenAt: Date? { views.compactMap(\.lastSeenAt).max() }
  var unseenOpens: Int { max(0, totalOpens - acknowledgedOpens) }
  var isActive: Bool { status == .open && expiresAt > Date() }
  var canShare: Bool { !token.isBlank }
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

/// Aggregate activity for one UTC calendar day. The backend never stores an
/// event trail, IP address, location, or viewer identity: charts only need
/// these three totals.
struct SmartLinkDailyActivity: Identifiable, Codable, Equatable {
  var day: String
  var opens: Int
  var seconds: Int
  var downloads: Int

  var id: String { day }

  /// Charts need a Date axis. Interpret the backend's date-only key as a local
  /// calendar label so it never slides into an adjacent day on the device.
  var date: Date? {
    let components = day.split(separator: "-").compactMap { Int($0) }
    guard components.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(
      year: components[0], month: components[1], day: components[2], hour: 12
    ))
  }
}

extension SmartLink {
  /// A fresh capability token in the backend's accepted alphabet.
  static func newToken() -> String {
    let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
    return String((0..<40).compactMap { _ in alphabet.randomElement() })
  }
}
