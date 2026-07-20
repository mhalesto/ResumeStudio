import Foundation

/// Where a request to confirm a claim has got to. Mirrors the statuses in
/// `functions/src/attestation-policy.js`, which treats everything except
/// `pending` as final.
enum AttestationStatus: String, Codable, CaseIterable, Identifiable {
  case pending
  case confirmed
  case declined
  case expired
  case revoked

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .pending: "Awaiting a reply"
    case .confirmed: "Confirmed"
    case .declined: "Not confirmed"
    case .expired: "Expired unanswered"
    case .revoked: "Link disabled"
    }
  }

  var systemImage: String {
    switch self {
    case .pending: "clock.fill"
    case .confirmed: "checkmark.seal.fill"
    case .declined: "xmark.seal.fill"
    case .expired: "hourglass.bottomhalf.filled"
    case .revoked: "slash.circle.fill"
    }
  }

  var isOpen: Bool { self == .pending }
}

/// One request for someone else to confirm one claim from the evidence vault.
///
/// This is deliberately separate from `CareerEvidence.isVerified`, which means
/// "I have a source for this" and is set by the owner. An attestation is a
/// different and stronger thing — somebody else said so — and conflating the two
/// would let a self-tick masquerade as a reference.
struct EvidenceAttestation: Identifiable, Codable, Equatable {
  var id = UUID()
  var evidenceID: UUID
  /// Server-issued. Whoever holds it can answer, which is exactly why the app
  /// never claims the responder's identity was checked.
  var token: String
  var claim: String
  var context: String
  var status: AttestationStatus
  var verifierName: String
  var verifierRole: String
  var comment: String
  var requestedAt = Date()
  var respondedAt: Date?
  var expiresAt: Date

  var isConfirmed: Bool { status == .confirmed }

  /// How the confirmation should be attributed wherever it is shown. Never the
  /// word "verified" on its own — see `EvidenceAttestation.assuranceNote`.
  var attributionText: String {
    let name = verifierName.nilIfBlank ?? "a referee"
    let role = verifierRole.nilIfBlank
    return role.map { "Confirmed by \(name), \($0)" } ?? "Confirmed by \(name)"
  }

  /// The sentence that must accompany any displayed confirmation, in the app and
  /// on the hosted page. The feature is worth having *and* it cannot prove who
  /// replied; both facts travel together.
  static let assuranceNote = """
    ResumeStudio records that someone holding your link replied, when, and what \
    they wrote. It does not check who they are.
    """
}

extension Array where Element == EvidenceAttestation {
  func attestation(for evidenceID: UUID) -> EvidenceAttestation? {
    // A confirmation outranks an open request for the same claim.
    first { $0.evidenceID == evidenceID && $0.isConfirmed }
      ?? first { $0.evidenceID == evidenceID && $0.status.isOpen }
      ?? first { $0.evidenceID == evidenceID }
  }
}
