import CoreGraphics
import Foundation

/// The recruiter's first pass, measured. The 2018 Ladders eye-tracking study
/// put the initial screen at 7.4 seconds, with roughly 80% of gaze time on six
/// data points: name, current title and company, previous title and company,
/// the dates on both, and education. The scan simulation and its report are
/// built from those numbers — the ATS checker answers "will the machine read
/// it?"; this answers "what does the human leave with?".
enum RecruiterScanStudy {
  /// Average length of a recruiter's initial resume screen, in seconds.
  static let scanSeconds: Double = 7.4
}

/// How demanding the simulated recruiter is. The fixation points never change —
/// only the bar each one has to clear: how much proof the first bullet needs,
/// how complete the trajectory must be, how tight the summary should read.
enum RecruiterScanStrictness: String, CaseIterable, Identifiable, Codable {
  case low
  case medium
  case high

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .low: "Low"
    case .medium: "Medium"
    case .high: "High"
    }
  }

  var detail: LocalizedStringResource {
    switch self {
    case .low: "A generous first read — forgiving of an early career and prose bullets."
    case .medium: "The study's averages, as measured. The default."
    case .high: "A competitive senior screen: numbers up front, dates everywhere, no dead space."
    }
  }
}

/// One of the study's fixation points, audited against the résumé. `severity`
/// reuses the ATS scale so the two reports read as one family: pass, warning,
/// action. Points are weighted by the gaze share each fixation claims, so the
/// score means "how much of the 7.4 seconds lands on real information".
struct RecruiterScanFinding: Identifiable, Equatable {
  let id: String
  let title: String
  /// Approximate share of the scan this fixation claims, in seconds.
  let gazeSeconds: Double
  let severity: ATSIssueSeverity
  let detail: String
  /// The editor section that fixes it, when one does.
  let section: ResumeSection?
  let points: Int
  let maxPoints: Int
}

/// Context the scan surfaces without scoring it: the portrait's pull on the
/// eye, a facts rail that matches how recruiters hunt, dark paper in a white
/// stack. These are trade-offs the user chose, not defects.
struct RecruiterScanNote: Identifiable, Equatable {
  let id: String
  let icon: String
  let title: String
  let detail: String
}

/// A stop on the simulated gaze path, in normalized page coordinates —
/// (0, 0) is the page's top-leading corner, (1, 1) its bottom-trailing one —
/// so the view can replay the scan over any rendered page size.
struct RecruiterGazeStop: Equatable {
  let point: CGPoint
  /// Dwell time at this stop, in seconds. All stops sum to `scanSeconds`.
  let duration: Double
  let label: String
}

struct RecruiterScanReport: Equatable {
  let findings: [RecruiterScanFinding]
  let notes: [RecruiterScanNote]
  /// What the recruiter leaves the scan holding — one line per confirmed point.
  let capturedFacts: [String]
  /// What they looked for and did not find.
  let missedFacts: [String]

  var score: Int {
    let maximum = findings.reduce(0) { $0 + $1.maxPoints }
    guard maximum > 0 else { return 0 }
    let earned = findings.reduce(0) { $0 + $1.points }
    return Int((Double(earned) / Double(maximum) * 100).rounded())
  }

  var verdict: LocalizedStringResource {
    switch score {
    case 85...: "Survives the first pass"
    case 65..<85: "Scan-ready, with gaps"
    case 40..<65: "The scan slips through"
    default: "Invisible in seven seconds"
    }
  }

  var verdictDetail: LocalizedStringResource {
    switch score {
    case 85...:
      "A recruiter leaves these seven seconds holding your name, your current role, your trajectory and at least one proof point."
    case 65..<85:
      "Most of the scan lands, but part of the recruiter's checklist comes up empty. The fixes below are ordered by how much gaze time they claim."
    case 40..<65:
      "Several of the six fixation points recruiters check have nothing to land on yet, so the first pass ends without a story."
    default:
      "Almost none of the scan finds what it is looking for. Fill the basics below before worrying about wording."
    }
  }
}
