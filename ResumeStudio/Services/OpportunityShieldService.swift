import CryptoKit
import Foundation

struct OpportunityPostingMetadata: Equatable {
  var title: String?
  var organization: String?
  var employerWebsite: String?
  var datePosted: Date?
  var validThrough: Date?
  var location: String?
  var employmentType: String?
}

enum OpportunityShieldService {
  private static let knownJobBoardDomains = [
    "ashbyhq.com", "breezy.hr", "careerjunction.co.za", "careers24.com",
    "glassdoor.com", "greenhouse.io", "indeed.com", "lever.co", "linkedin.com",
    "myworkdayjobs.com", "pnet.co.za", "smartrecruiters.com", "workdayjobs.com",
  ]

  private static let freeEmailDomains = [
    "gmail.com", "googlemail.com", "hotmail.com", "icloud.com", "live.com",
    "outlook.com", "proton.me", "protonmail.com", "yahoo.com", "yandex.com",
  ]

  private static let paymentTrapPhrases = [
    "application fee", "background check fee", "cash app", "cashapp", "crypto wallet",
    "cryptocurrency", "deposit a check", "deposit a cheque", "gift card", "pay for equipment",
    "pay for training", "pay to apply", "purchase equipment", "refundable fee",
    "registration fee", "send money", "send part of the money", "training fee",
    "transfer money", "wire transfer", "zelle",
  ]

  private static let earlyDataPhrases = [
    "bank account before", "banking details before", "copy of your id",
    "driver's licence before", "driver's license before", "passport before",
    "send your id", "social security number before",
  ]

  static func analyze(
    role: String,
    company: String,
    location: String,
    salary: String,
    responsibilities: [String],
    requirements: [String],
    content: String,
    sourceURL: String,
    structuredPosting: String?,
    recruiterMessage: String = "",
    previous: OpportunitySignalReport? = nil,
    pageInspection: OpportunityPageInspection? = nil,
    now: Date = Date()
  ) -> OpportunitySignalReport {
    let metadata = metadata(from: structuredPosting)
    let searchable = "\(content)\n\(recruiterMessage)".lowercased()
    let sourceHost = normalizedHost(sourceURL)
    let employerHost = normalizedHost(metadata.employerWebsite ?? "")
    var findings: [OpportunitySignalFinding] = []

    addFreshnessFindings(
      metadata: metadata,
      pageInspection: pageInspection,
      now: now,
      to: &findings
    )
    addEmployerFindings(
      company: company,
      sourceURL: sourceURL,
      sourceHost: sourceHost,
      employerHost: employerHost,
      metadata: metadata,
      to: &findings
    )
    addListingFindings(
      content: content,
      location: location,
      salary: salary,
      responsibilities: responsibilities,
      requirements: requirements,
      to: &findings
    )
    addSafetyFindings(searchable: searchable, to: &findings)

    let digest = hash(normalized(content))
    let fingerprint = hash(normalized([role, company, location].joined(separator: "|")))
    var repostCount = previous?.repostCount ?? 0
    if let oldDate = previous?.datePosted, let newDate = metadata.datePosted,
      newDate.timeIntervalSince(oldDate) > 2 * 24 * 60 * 60
    {
      repostCount += 1
      findings.append(finding(
        "freshness-reposted", .freshness, .caution, "Posting date moved forward",
        "The advertised date is newer than the last saved check. This can be a repost; confirm the employer is actively filling the role."
      ))
    } else if let previous, previous.contentDigest != digest,
      pageInspection?.status == .live
    {
      findings.append(finding(
        "freshness-changed", .freshness, .information, "Listing content changed",
        "The live advert differs from the version you captured. Review it before applying or following up."
      ))
    }

    let dangerCount = findings.filter { $0.severity == .danger }.count
    let cautionCount = findings.filter { $0.severity == .caution }.count
    let positiveCount = findings.filter { $0.severity == .positive }.count
    let band: OpportunitySignalBand
    if dangerCount > 0 {
      band = .highRisk
    } else if cautionCount >= 2 || (cautionCount == 1 && positiveCount < 3) {
      band = .verify
    } else {
      band = .strong
    }

    var evidenceScore = 0
    if structuredPosting != nil { evidenceScore += 3 }
    if sourceHost != nil { evidenceScore += 1 }
    if content.split(whereSeparator: \.isWhitespace).count >= 80 { evidenceScore += 1 }
    if pageInspection != nil { evidenceScore += 1 }
    if !role.isBlank && !company.isBlank { evidenceScore += 1 }
    let confidence: OpportunitySignalConfidence = evidenceScore >= 6
      ? .strong : evidenceScore >= 3 ? .useful : .limited

    var history = previous?.checkHistory ?? []
    if let pageInspection {
      history.append(OpportunityCheckRecord(
        checkedAt: pageInspection.checkedAt,
        pageStatus: pageInspection.status,
        postingDate: metadata.datePosted,
        contentDigest: digest
      ))
      history = Array(history.suffix(8))
    }

    return OpportunitySignalReport(
      band: band,
      confidence: confidence,
      findings: sorted(findings),
      checkedAt: now,
      datePosted: metadata.datePosted,
      validThrough: metadata.validThrough,
      employerWebsite: metadata.employerWebsite,
      postingFingerprint: fingerprint,
      contentDigest: digest,
      repostCount: repostCount,
      pageStatus: pageInspection?.status ?? previous?.pageStatus ?? .notChecked,
      pageCheckedAt: pageInspection?.checkedAt ?? previous?.pageCheckedAt,
      checkHistory: history
    )
  }

  static func metadata(from rawPosting: String?) -> OpportunityPostingMetadata {
    guard let data = rawPosting?.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return OpportunityPostingMetadata() }

    let organization = object["hiringOrganization"] as? [String: Any]
    let website = firstString(in: organization, keys: ["sameAs", "url"])
    return OpportunityPostingMetadata(
      title: string(object["title"]),
      organization: string(organization?["name"]),
      employerWebsite: website,
      datePosted: date(from: string(object["datePosted"])),
      validThrough: date(from: string(object["validThrough"])),
      location: describedLocation(object),
      employmentType: string(object["employmentType"])
    )
  }

  private static func addFreshnessFindings(
    metadata: OpportunityPostingMetadata,
    pageInspection: OpportunityPageInspection?,
    now: Date,
    to findings: inout [OpportunitySignalFinding]
  ) {
    if let pageInspection {
      switch pageInspection.status {
      case .live:
        findings.append(finding(
          "freshness-page-live", .freshness, .positive, "Public listing still matches",
          "The public page still contains the saved role and employer."
        ))
      case .removed:
        findings.append(finding(
          "freshness-page-removed", .freshness, .danger, "Public listing was removed",
          "The source page says the role is closed, filled, expired or no longer available."
        ))
      case .inconclusive:
        findings.append(finding(
          "freshness-page-inconclusive", .freshness, .caution, "Public page is inconclusive",
          "The page loaded but no longer clearly matched both the saved role and employer."
        ))
      case .unreachable:
        findings.append(finding(
          "freshness-page-unreachable", .freshness, .information, "Public page could not be checked",
          "The site blocked or failed the request. This is not evidence that the role is closed."
        ))
      case .notChecked: break
      }
    } else {
      findings.append(finding(
        "freshness-page-unchecked", .freshness, .information, "Public page not checked",
        "Add a source link to monitor whether the listing stays available."
      ))
    }

    if let expiry = metadata.validThrough {
      if expiry < Calendar.current.startOfDay(for: now) {
        findings.append(finding(
          "freshness-expired", .freshness, .danger, "Advertised deadline has passed",
          "The structured listing says applications closed on \(expiry.formatted(date: .abbreviated, time: .omitted))."
        ))
      } else {
        findings.append(finding(
          "freshness-deadline", .freshness, .positive, "Deadline is still ahead",
          "The advertised closing date is \(expiry.formatted(date: .abbreviated, time: .omitted))."
        ))
      }
    }

    guard let posted = metadata.datePosted else {
      findings.append(finding(
        "freshness-date-missing", .freshness, .information, "No machine-readable posting date",
        "The source did not expose a reliable date, so freshness needs manual confirmation."
      ))
      return
    }
    let days = Calendar.current.dateComponents([.day], from: posted, to: now).day ?? 0
    if days < -1 {
      findings.append(finding(
        "freshness-date-future", .freshness, .caution, "Posting date is in the future",
        "The source date may be incorrect or scheduled for later publication."
      ))
    } else if days <= 45 {
      findings.append(finding(
        "freshness-recent", .freshness, .positive, "Recently posted",
        "The source date is \(posted.formatted(date: .abbreviated, time: .omitted))."
      ))
    } else if days > 120 {
      findings.append(finding(
        "freshness-stale", .freshness, .caution, "Posting is more than four months old",
        "Confirm that the employer is still actively hiring before tailoring an application."
      ))
    } else if days > 60 {
      findings.append(finding(
        "freshness-aging", .freshness, .information, "Posting is more than two months old",
        "The role may still be open, but freshness is worth confirming on the employer's site."
      ))
    }
  }

  private static func addEmployerFindings(
    company: String,
    sourceURL: String,
    sourceHost: String?,
    employerHost: String?,
    metadata: OpportunityPostingMetadata,
    to findings: inout [OpportunitySignalFinding]
  ) {
    if URL(string: sourceURL)?.scheme?.lowercased() == "https" {
      findings.append(finding(
        "employer-https", .employer, .positive, "Source uses a secure connection",
        "The public listing was captured over HTTPS."
      ))
    } else if sourceHost != nil {
      findings.append(finding(
        "employer-http", .employer, .caution, "Source is not using HTTPS",
        "Avoid entering personal information on an unencrypted page."
      ))
    }

    if let employerHost, let sourceHost {
      if sameOrganization(sourceHost, employerHost) {
        findings.append(finding(
          "employer-domain-match", .employer, .positive, "Employer domain matches",
          "The source and the organization website published in the advert share the same domain."
        ))
      } else if knownJobBoardDomains.contains(where: { sourceHost == $0 || sourceHost.hasSuffix(".\($0)") }) {
        findings.append(finding(
          "employer-board", .employer, .information, "Hosted by a known job platform",
          "The listing points to \(employerHost) as the employer website. Confirm the same role there when possible."
        ))
      } else {
        findings.append(finding(
          "employer-third-party", .employer, .caution, "Source differs from employer website",
          "The advert is on \(sourceHost), while its employer website is \(employerHost). Confirm the relationship before sharing sensitive data."
        ))
      }
    } else if let sourceHost,
      knownJobBoardDomains.contains(where: { sourceHost == $0 || sourceHost.hasSuffix(".\($0)") })
    {
      findings.append(finding(
        "employer-board-no-site", .employer, .information, "Employer website was not supplied",
        "This job-board listing does not expose an employer website. Search the employer's own careers page before applying."
      ))
    } else if sourceHost == nil {
      findings.append(finding(
        "employer-source-missing", .employer, .caution, "No verifiable source link",
        "A copied advert alone cannot confirm who published the role. Add the employer's careers-page link if available."
      ))
    }

    if company.isBlank && (metadata.organization ?? "").isBlank {
      findings.append(finding(
        "employer-name-missing", .employer, .caution, "Employer identity is unclear",
        "The saved advert does not clearly identify the hiring organization."
      ))
    }
  }

  private static func addListingFindings(
    content: String,
    location: String,
    salary: String,
    responsibilities: [String],
    requirements: [String],
    to findings: inout [OpportunitySignalFinding]
  ) {
    let words = content.split(whereSeparator: \.isWhitespace).count
    if words >= 150 && !responsibilities.isEmpty && !requirements.isEmpty {
      findings.append(finding(
        "listing-specific", .listing, .positive, "Role has specific work and requirements",
        "The advert contains enough concrete detail to evaluate fit and tailor evidence."
      ))
    } else if words >= 80 {
      findings.append(finding(
        "listing-partial", .listing, .information, "Role has some useful detail",
        "The advert is readable but responsibilities or requirements could be more specific."
      ))
    } else {
      findings.append(finding(
        "listing-thin", .listing, .caution, "Advert is unusually thin",
        "Very short or vague adverts are harder to verify and tailor against. Ask for a full job specification."
      ))
    }

    findings.append(salary.isBlank
      ? finding(
        "listing-pay-missing", .listing, .information, "No pay range found",
        "Missing pay is common, but a published range makes an opportunity easier to compare."
      )
      : finding(
        "listing-pay", .listing, .positive, "Pay information is present",
        "The captured advert includes compensation information."
      ))

    if !location.isBlank {
      findings.append(finding(
        "listing-location", .listing, .positive, "Work location is stated",
        "The role gives a location or work arrangement to verify."
      ))
    }
  }

  private static func addSafetyFindings(
    searchable: String,
    to findings: inout [OpportunitySignalFinding]
  ) {
    let hasPaymentTrap = paymentTrapPhrases.contains(where: searchable.contains)
    let hasEarlyDataRequest = earlyDataPhrases.contains(where: searchable.contains)
    let hasMessagingOnly = (searchable.contains("whatsapp") || searchable.contains("telegram"))
      && (searchable.contains("only") || searchable.contains("contact"))
    let freeEmail = detectedFreeEmailDomain(in: searchable)

    if hasPaymentTrap {
      findings.append(finding(
        "safety-payment", .safety, .danger, "Payment or money-transfer language found",
        "Legitimate employers should not require applicants to pay, buy gift cards, move money or deposit a cheque for equipment."
      ))
    }
    if hasEarlyDataRequest {
      findings.append(finding(
        "safety-personal-data", .safety, .danger, "Sensitive-data request appears too early",
        "Do not send banking or identity documents before independently verifying the employer and hiring process."
      ))
    }
    if hasMessagingOnly {
      findings.append(finding(
        "safety-message-only", .safety, .caution, "Messaging-only contact requested",
        "Confirm the recruiter through the employer's published switchboard, website or company email before continuing."
      ))
    }
    if let freeEmail {
      findings.append(finding(
        "safety-free-email", .safety, .caution, "Recruiter uses a free email domain",
        "A \(freeEmail) address can be legitimate, but it does not prove a connection to the employer. Verify it independently."
      ))
    }
    if !hasPaymentTrap && !hasEarlyDataRequest && !hasMessagingOnly && freeEmail == nil {
      findings.append(finding(
        "safety-no-common-traps", .safety, .positive, "No common applicant traps found",
        "The saved text contains no obvious fee, money-transfer, early identity-document or messaging-only request. This is a signal, not a guarantee."
      ))
    }
  }

  private static func sorted(_ findings: [OpportunitySignalFinding]) -> [OpportunitySignalFinding] {
    let severity: [OpportunitySignalSeverity: Int] = [
      .danger: 0, .caution: 1, .information: 2, .positive: 3,
    ]
    let category = Dictionary(
      uniqueKeysWithValues: OpportunitySignalCategory.allCases.enumerated().map { ($1, $0) })
    return findings.sorted {
      (severity[$0.severity] ?? 9, category[$0.category] ?? 9, $0.id)
        < (severity[$1.severity] ?? 9, category[$1.category] ?? 9, $1.id)
    }
  }

  private static func finding(
    _ id: String,
    _ category: OpportunitySignalCategory,
    _ severity: OpportunitySignalSeverity,
    _ title: LocalizedStringResource,
    _ detail: LocalizedStringResource
  ) -> OpportunitySignalFinding {
    OpportunitySignalFinding(
      id: id,
      category: category,
      severity: severity,
      title: String(localized: title),
      detail: String(localized: detail)
    )
  }

  private static func detectedFreeEmailDomain(in text: String) -> String? {
    guard !text.isBlank,
      let regex = try? NSRegularExpression(
        pattern: "[A-Z0-9._%+-]+@([A-Z0-9.-]+\\.[A-Z]{2,})",
        options: [.caseInsensitive]
      )
    else { return nil }
    let source = text as NSString
    for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length))
    where match.numberOfRanges > 1 {
      let domain = source.substring(with: match.range(at: 1)).lowercased()
      if freeEmailDomains.contains(domain) { return domain }
    }
    return nil
  }

  private static func normalized(_ text: String) -> String {
    text.lowercased()
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  private static func hash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func normalizedHost(_ value: String) -> String? {
    guard let host = URL(string: value)?.host()?.lowercased() else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  private static func sameOrganization(_ lhs: String, _ rhs: String) -> Bool {
    registrableDomain(lhs) == registrableDomain(rhs)
  }

  private static func registrableDomain(_ host: String) -> String {
    let components = host.split(separator: ".").map(String.init)
    guard components.count > 2 else { return host }
    let twoPartSuffixes = Set(["ac.za", "co.nz", "co.uk", "co.za", "com.au", "gov.za", "org.uk", "org.za"])
    let suffix = components.suffix(2).joined(separator: ".")
    let count = twoPartSuffixes.contains(suffix) ? 3 : 2
    return components.suffix(count).joined(separator: ".")
  }

  private static func firstString(in dictionary: [String: Any]?, keys: [String]) -> String? {
    for key in keys {
      if let value = string(dictionary?[key]) { return value }
    }
    return nil
  }

  private static func string(_ value: Any?) -> String? {
    if let value = value as? String, !value.isBlank { return value }
    if let values = value as? [String] { return values.first(where: { !$0.isBlank }) }
    return nil
  }

  private static func date(from value: String?) -> Date? {
    guard let value else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: value) { return date }
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: value) { return date }
    let day = DateFormatter()
    day.locale = Locale(identifier: "en_US_POSIX")
    day.calendar = Calendar(identifier: .gregorian)
    day.dateFormat = "yyyy-MM-dd"
    return day.date(from: value)
  }

  private static func describedLocation(_ object: [String: Any]) -> String? {
    if string(object["jobLocationType"]) == "TELECOMMUTE" { return "Remote" }
    let raw = object["jobLocation"]
    let location = (raw as? [[String: Any]])?.first ?? raw as? [String: Any]
    let address = location?["address"] as? [String: Any]
    let parts = [
      string(address?["addressLocality"]), string(address?["addressRegion"]),
      string(address?["addressCountry"]),
    ].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }
}

@MainActor
enum OpportunityShieldMonitor {
  static func refreshDue(
    in store: ApplicationStore,
    limit: Int = 4,
    now: Date = Date()
  ) async {
    let due = store.applications
      .filter {
        $0.status == .saved && !$0.sourceURL.isBlank && $0.capturedOpportunity != nil
          && ($0.capturedOpportunity?.opportunitySignal?.pageCheckedAt.map {
            now.timeIntervalSince($0) >= 24 * 60 * 60
          } ?? true)
      }
      .sorted { ($0.capturedOpportunity?.opportunitySignal?.pageCheckedAt ?? .distantPast)
        < ($1.capturedOpportunity?.opportunitySignal?.pageCheckedAt ?? .distantPast) }
      .prefix(limit)

    for application in due {
      store.update(await refreshed(application, now: now))
    }
  }

  static func refreshed(_ application: JobApplication, now: Date = Date()) async -> JobApplication {
    guard var snapshot = application.capturedOpportunity, !application.sourceURL.isBlank else {
      return application
    }
    let inspection = await JobCaptureService.inspect(
      rawURL: application.sourceURL,
      expectedRole: application.role,
      expectedCompany: application.company,
      checkedAt: now
    )
    let structuredPosting = inspection.structuredPosting ?? snapshot.structuredPosting
    snapshot.structuredPosting = structuredPosting
    snapshot.opportunitySignal = OpportunityShieldService.analyze(
      role: application.role,
      company: application.company,
      location: snapshot.location,
      salary: snapshot.salary,
      responsibilities: snapshot.responsibilities,
      requirements: snapshot.requirements,
      content: inspection.readableText.nilIfBlank ?? snapshot.originalContent,
      sourceURL: application.sourceURL,
      structuredPosting: structuredPosting,
      recruiterMessage: snapshot.recruiterMessage ?? "",
      previous: snapshot.opportunitySignal,
      pageInspection: inspection,
      now: now
    )
    var updated = application
    updated.capturedOpportunity = snapshot
    return updated
  }
}
