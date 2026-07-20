import Foundation

/// A job board the app will open for browsing.
///
/// The app never fetches, crawls or re-publishes any of these — a board opens in
/// Safari, signed in as the reader already is, and a posting only reaches
/// ResumeStudio when they share it. That is the whole of the relationship, and
/// it is why this is a list of destinations rather than a search index.
struct JobBoard: Identifiable, Hashable {
  var id: String { url }
  let name: String
  let url: String
  /// What kind of hiring it carries, so the list reads as a shelf rather than
  /// eight names in a row.
  let note: LocalizedStringResource

  var host: String { URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? url }

  // A localised note is not hashable, and the address already identifies a board.
  static func == (lhs: JobBoard, rhs: JobBoard) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum JobBoardCatalogue {
  /// The boards worth opening first in a given market, most general first.
  /// Deliberately short: this is a starting point for browsing, not a directory.
  static func boards(for market: ResumeMarket) -> [JobBoard] {
    local(for: market) + global
  }

  private static func local(for market: ResumeMarket) -> [JobBoard] {
    switch market {
    case .southAfrica:
      [
        JobBoard(
          name: "PNet", url: "https://www.pnet.co.za",
          note: "South Africa's largest professional board"),
        JobBoard(
          name: "Careers24", url: "https://www.careers24.com",
          note: "Broad South African listings"),
        JobBoard(
          name: "OfferZen", url: "https://www.offerzen.com",
          note: "Software roles, companies apply to you"),
      ]
    case .unitedKingdom:
      [
        JobBoard(name: "Reed", url: "https://www.reed.co.uk", note: "Broad UK listings"),
        JobBoard(
          name: "Totaljobs", url: "https://www.totaljobs.com", note: "Broad UK listings"),
      ]
    case .unitedStates:
      [
        JobBoard(
          name: "Dice", url: "https://www.dice.com", note: "Technology roles"),
        JobBoard(
          name: "Built In", url: "https://builtin.com", note: "Startup and tech roles"),
      ]
    case .australia:
      [JobBoard(name: "Seek", url: "https://www.seek.com.au", note: "Broad Australian listings")]
    case .canada:
      [JobBoard(name: "Job Bank", url: "https://www.jobbank.gc.ca", note: "Government of Canada")]
    case .europeanUnion:
      [
        JobBoard(
          name: "EURES", url: "https://eures.europa.eu", note: "European Commission portal")
      ]
    case .international:
      []
    }
  }

  /// Boards worth having wherever you are.
  private static let global: [JobBoard] = [
    JobBoard(
      name: "LinkedIn", url: "https://www.linkedin.com/jobs",
      note: "Roles from your network and beyond"),
    JobBoard(
      name: "Indeed", url: "https://www.indeed.com", note: "The widest general listing"),
    JobBoard(
      name: "Otta", url: "https://otta.com", note: "Curated technology and startup roles"),
    JobBoard(
      name: "Wellfound", url: "https://wellfound.com", note: "Startup roles and equity"),
    JobBoard(
      name: "Remote OK", url: "https://remoteok.com", note: "Remote-first listings"),
  ]
}

/// A search the reader set up themselves — a board URL already narrowed to their
/// role, place and filters. The point of the browser screen: two taps back to
/// the exact list they were working through yesterday.
struct SavedJobSearch: Identifiable, Codable, Equatable, Hashable {
  var id = UUID()
  var name: String
  var url: String
  var createdAt = Date()

  var host: String { URL(string: url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? url }
}

/// Stored as JSON in `UserDefaults`: a handful of short strings that only matter
/// on this device, which is not worth a store of its own.
enum SavedJobSearchStore {
  static let key = "savedJobSearches"

  static func load() -> [SavedJobSearch] {
    guard let data = UserDefaults.standard.data(forKey: key),
      let searches = try? JSONDecoder().decode([SavedJobSearch].self, from: data)
    else { return [] }
    return searches
  }

  static func save(_ searches: [SavedJobSearch]) {
    guard let data = try? JSONEncoder().encode(searches) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }

  /// Only http(s) is ever opened, so a stored string cannot become a way to
  /// reach another app through a custom scheme.
  static func normalised(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http", url.host?.isEmpty == false
    else { return nil }
    return url
  }
}
