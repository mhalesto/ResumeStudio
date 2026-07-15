import Foundation

enum MarketSourceCatalog {
  static let checkedAt = ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z") ?? Date()

  static let all: [MarketGuidanceSource] = [
    MarketGuidanceSource(
      market: .southAfrica,
      title: "Protection of Personal Information Act",
      publisher: "South African Department of Justice",
      url: "https://www.justice.gov.za/legislation/acts/2013-004.pdf",
      checkedAt: checkedAt,
      note: "Primary legislation for handling personal information. Resume conventions are guidance, not legal requirements."
    ),
    MarketGuidanceSource(
      market: .unitedKingdom,
      title: "Recruitment and selection data protection",
      publisher: "Information Commissioner's Office",
      url: "https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/employment/recruitment-and-selection/",
      checkedAt: checkedAt,
      note: "Official recruitment privacy guidance; distinguish legal duties from common CV practice."
    ),
    MarketGuidanceSource(
      market: .unitedStates,
      title: "Prohibited employment practices and pre-employment inquiries",
      publisher: "U.S. Equal Employment Opportunity Commission",
      url: "https://www.eeoc.gov/prohibited-employment-policiespractices",
      checkedAt: checkedAt,
      note: "Official guidance on protected characteristics and job-related applicant information."
    ),
    MarketGuidanceSource(
      market: .europeanUnion,
      title: "GDPR data-processing principles",
      publisher: "European Commission",
      url: "https://commission.europa.eu/law/law-topic/data-protection/rules-business-and-organisations/principles-gdpr/overview-principles/what-data-can-we-process-and-under-which-conditions_en",
      checkedAt: checkedAt,
      note: "Official principles including data minimisation, purpose limitation and accuracy."
    ),
    MarketGuidanceSource(
      market: .australia,
      title: "Privacy and employment",
      publisher: "Office of the Australian Information Commissioner",
      url: "https://www.oaic.gov.au/privacy/your-privacy-rights/more-privacy-rights/employment",
      checkedAt: checkedAt,
      note: "Official privacy overview for applicants and employees."
    ),
    MarketGuidanceSource(
      market: .canada,
      title: "Privacy in the workplace",
      publisher: "Office of the Privacy Commissioner of Canada",
      url: "https://www.priv.gc.ca/en/privacy-topics/employers-and-employees/",
      checkedAt: checkedAt,
      note: "Official federal privacy resources; provincial requirements can differ."
    ),
  ]
}
