import Foundation

/// A group of fields in the editor.
///
/// Naming the sections lets the app answer "what do I do next?": the home screen
/// points at the first incomplete one and the editor scrolls straight to it.
enum ResumeSection: String, CaseIterable, Identifiable, Hashable, Codable {
  case personal
  case profile
  case competencies
  case experience
  case education
  case references

  var id: String { rawValue }

  var title: String {
    switch self {
    case .personal: "Personal details"
    case .profile: "Professional profile"
    case .competencies: "Core competencies"
    case .experience: "Experience"
    case .education: "Education"
    case .references: "References"
    }
  }

  /// What to do in this section. Kept short: it has to fit on one line in the
  /// hero's "Next up" row, alongside an icon and a chevron.
  var prompt: String {
    switch self {
    case .personal: "Add your contact details"
    case .profile: "Write a short summary"
    case .competencies: "List your key skills"
    case .experience: "Add a role you've held"
    case .education: "Add a qualification"
    case .references: "Add a reference"
    }
  }

  var systemImage: String {
    switch self {
    case .personal: "person.crop.circle.fill"
    case .profile: "text.alignleft"
    case .competencies: "checkmark.seal.fill"
    case .experience: "briefcase.fill"
    case .education: "graduationcap.fill"
    case .references: "person.2.fill"
    }
  }
}
