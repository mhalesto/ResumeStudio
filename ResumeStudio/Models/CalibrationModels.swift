import Foundation

/// What a calibration pass found in the application history. Every kind except
/// `steadyProgress` names something the search is getting wrong, so the wording
/// throughout is deliberately plain: this feature exists to say the thing a
/// résumé product is normally too polite to say.
enum CalibrationSignalKind: String, Codable, CaseIterable, Identifiable {
  case notEnoughData
  case responseDrought
  case reachGap
  case matchAdvantage
  case sourceConcentration
  case steadyProgress

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .notEnoughData: "Not enough history yet"
    case .responseDrought: "Volume is not the problem"
    case .reachGap: "You are aiming past your evidence"
    case .matchAdvantage: "Well-matched roles are carrying you"
    case .sourceConcentration: "One source is doing all the work"
    case .steadyProgress: "This is working"
    }
  }

  var systemImage: String {
    switch self {
    case .notEnoughData: "hourglass"
    case .responseDrought: "exclamationmark.triangle.fill"
    case .reachGap: "arrow.up.forward.circle.fill"
    case .matchAdvantage: "target"
    case .sourceConcentration: "arrow.triangle.branch"
    case .steadyProgress: "checkmark.seal.fill"
    }
  }

  /// Whether the signal reports something that is working. The UI uses this to
  /// avoid dressing good news in warning colours.
  var isEncouraging: Bool {
    switch self {
    case .matchAdvantage, .steadyProgress: true
    case .notEnoughData, .responseDrought, .reachGap, .sourceConcentration: false
    }
  }
}

/// How much weight a signal has earned. A pattern seen four times and a pattern
/// seen twenty times get different sentences, because the app never lets a small
/// sample read like a settled fact.
enum CalibrationConfidence: String, Codable, Equatable, CaseIterable {
  case provisional
  case emerging
  case consistent

  var title: LocalizedStringResource {
    switch self {
    case .provisional: "Provisional"
    case .emerging: "Emerging"
    case .consistent: "Consistent"
    }
  }

  /// Appended to every signal, so a number can never be mistaken for a verdict.
  var caveat: LocalizedStringResource {
    switch self {
    case .provisional:
      "This is a hypothesis from a small sample. Test it before you rebuild anything."
    case .emerging:
      "The pattern has repeated, but the sample is still small. Treat it as a direction, not a diagnosis."
    case .consistent:
      "This has held across your recorded history. It is still a correlation, not a cause."
    }
  }
}

struct ApplicationCalibrationSignal: Identifiable, Equatable {
  var id: String
  var kind: CalibrationSignalKind
  var headline: String
  var detail: String
  /// The numbers the signal was drawn from, stated plainly.
  var evidence: String
  var confidence: CalibrationConfidence
  var sampleSize: Int
  /// Where the résumé work would happen, when the signal points at the document
  /// rather than at targeting. Reuses the existing outcome-learning routing.
  var focus: OutcomeLearningFocus?
  var applicationIDs: [UUID]
}

struct ApplicationCalibrationReport: Equatable {
  /// Ordered by how much the user needs to hear it, hardest truth first.
  var signals: [ApplicationCalibrationSignal]
  var settledCount: Int
  var progressedCount: Int
  var analyzedCount: Int

  var primary: ApplicationCalibrationSignal? { signals.first }

  /// Share of settled applications that reached interview or offer. Nil until
  /// there is anything settled to divide by.
  var progressionRate: Double? {
    guard settledCount > 0 else { return nil }
    return Double(progressedCount) / Double(settledCount)
  }

  var progressionRateText: String? {
    guard let rate = progressionRate else { return nil }
    return "\(Int((rate * 100).rounded()))%"
  }

  static let empty = ApplicationCalibrationReport(
    signals: [], settledCount: 0, progressedCount: 0, analyzedCount: 0
  )
}
