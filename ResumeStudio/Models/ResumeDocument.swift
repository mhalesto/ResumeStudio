import Foundation
import SwiftUI
import UIKit

struct ResumeDocument: Codable, Equatable, Hashable {
    var personal: PersonalDetails
    var professionalProfile: String
    var competencies: [String]
    var experience: [ExperienceEntry]
    var education: [EducationEntry]
    var references: [ReferenceEntry]
    var accent: ResumeAccent

    var suggestedFilename: String {
        let source = personal.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = source.isEmpty ? "Resume" : "\(source) Resume"
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return base.components(separatedBy: invalid).joined(separator: "-")
    }

    static let blank = ResumeDocument(
        personal: PersonalDetails(fullName: "", headline: "", phone: "", email: ""),
        professionalProfile: "",
        competencies: [],
        experience: [],
        education: [],
        references: [],
        accent: .orange
    )

    static let mandisaSample = ResumeDocument(
        personal: PersonalDetails(
            fullName: "Mandisa Nkabinde",
            headline: "HR Business Partner | Employee Relations",
            phone: "071 740 5898 / 078 509 2995",
            email: "Mandisankabinde21@gmail.com"
        ),
        professionalProfile: "Strategic and people-centered HR Business Partner with 5+ years of progressive experience across employee relations, talent acquisition, and HR compliance. Proven success in partnering with leadership to align HR strategies with business goals, manage complex employee relations issues, and enhance workplace culture. Experienced in navigating South African labour law, driving performance management processes, and delivering fair, legally compliant ER practices. Skilled in building trust, driving diversity and inclusion initiatives, and acting as a credible advisor to managers and employees alike. Global recruitment experience across multiple countries has broadened cultural awareness and strengthened adaptability in diverse environments.",
        competencies: [
            "Strategic HR Partnership & Workforce Planning",
            "Diversity, Equity & Inclusion",
            "Performance Management & Coaching",
            "Change Management & Organisational Development",
            "HR Analytics & Metrics",
            "Talent Acquisition & Employer Branding",
            "HR Administration & Compliance",
            "Communication & Advisory Skills",
            "Labour Law & Industrial Relations",
            "Employee Engagement & Development",
        ],
        experience: [
            ExperienceEntry(
                role: "Human Resources Business Partner",
                company: "Cubix Talksure Trading (Pty) Ltd",
                period: "Feb 2025 - 31 March 2026",
                highlights: [
                    "Partner with senior leadership to design and implement HR strategies aligned with business objectives, enhancing organisational performance.",
                    "Provide expert guidance on employee relations, performance management, and labour law compliance, ensuring fair and consistent practices.",
                    "Lead complex disciplinary processes and grievance procedures, representing the company in CCMA matters.",
                    "Drive initiatives that promote employee well-being, engagement, and a high-performance culture.",
                    "Conduct training on company policies and labour legislation to foster a compliant work environment.",
                    "Prepare and analyse HR metrics to support strategic decision-making and continuous improvement.",
                    "Support workforce planning and succession management by identifying critical roles and talent pipelines.",
                    "Champion diversity and inclusion programmes, increasing representation and employee participation.",
                ]
            ),
            ExperienceEntry(
                role: "Employee Relations Consultant",
                company: "Cubix Talksure Trading (Pty) Ltd",
                period: "Aug 2024 - Jan 2025",
                highlights: [
                    "Advised managers on employee relations matters, ensuring legally compliant and fair resolutions.",
                    "Conducted investigations into grievances and misconduct, recommending corrective action.",
                    "Supported organisational restructuring and policy updates, ensuring smooth transitions.",
                    "Promoted diversity, equity and inclusion initiatives alongside employee wellness programmes.",
                    "Developed ER case tracking systems to monitor trends and proactively address recurring issues.",
                    "Delivered workshops on conflict resolution and effective communication for line managers.",
                ]
            ),
            ExperienceEntry(
                role: "Talent Acquisition Specialist",
                company: "Capita SA / UK / ROI",
                period: "Jun 2022 - Apr 2024",
                highlights: [
                    "Managed end-to-end recruitment processes across South Africa, the UK, and ROI.",
                    "Partnered with hiring managers to design recruitment strategies aligned with business needs.",
                    "Conducted interviews and assessments to ensure quality hires and cultural fit.",
                    "Supported onboarding and induction programmes, ensuring seamless integration of new employees.",
                    "Monitored recruitment metrics to track progress and identify improvement areas.",
                    "Built talent pipelines for hard-to-fill roles, reducing time-to-hire.",
                    "Enhanced employer branding initiatives to attract diverse candidates.",
                    "Coordinated with global HR teams to maintain compliance with international hiring standards.",
                ]
            ),
            ExperienceEntry(
                role: "Junior Human Resources Business Partner",
                company: "Talksure Trading (Pty) Ltd",
                period: "Feb 2020 - Sep 2021",
                highlights: [
                    "Provided HR advisory services on employee relations, disciplinary procedures, and performance management.",
                    "Represented the company in CCMA proceedings and facilitated disciplinary hearings.",
                    "Oversaw onboarding processes and conducted exit interviews to inform retention strategies.",
                    "Drafted employment contracts, warning letters, and HR documentation.",
                    "Supported managers with performance improvement plans and coaching interventions.",
                    "Assisted in developing HR policies and procedures to strengthen compliance.",
                ]
            ),
        ],
        education: [
            EducationEntry(
                qualification: "Bachelor of Industrial Psychology & Psychology",
                institution: "University of KwaZulu-Natal",
                period: "2016 - 2019",
                details: ""
            ),
            EducationEntry(
                qualification: "BCom Honours in Industrial/Employment Relations",
                institution: "University of KwaZulu-Natal",
                period: "2019 - 2020",
                details: ""
            ),
            EducationEntry(
                qualification: "Master of Commerce in Industrial/Employment Relations",
                institution: "University of KwaZulu-Natal",
                period: "",
                details: "Coursework completed; research component pending. Studies currently on hold."
            ),
        ],
        references: [
            ReferenceEntry(
                name: "Triselle Munsamy",
                company: "Talksure Cubix",
                phone: "+27 84 220 7397",
                email: "Triselle.Munsamy@talksuresa.co.za"
            ),
            ReferenceEntry(
                name: "Philile Mbambo",
                company: "Capita",
                phone: "+27 73 095 8356",
                email: "Tymlesc@gmail.com"
            ),
        ],
        accent: .orange
    )
}

struct PersonalDetails: Codable, Equatable, Hashable {
    var fullName: String
    var headline: String
    var phone: String
    var email: String
}

struct ExperienceEntry: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var role: String
    var company: String
    var period: String
    var highlights: [String]
}

struct EducationEntry: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var qualification: String
    var institution: String
    var period: String
    var details: String
}

struct ReferenceEntry: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var company: String
    var phone: String
    var email: String
}

enum ResumeAccent: String, CaseIterable, Codable, Identifiable {
    case orange
    case blue
    case teal
    case burgundy

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var color: Color {
        Color(uiColor: uiColor)
    }

    var uiColor: UIColor {
        switch self {
        case .orange:
            UIColor(red: 0.82, green: 0.28, blue: 0.04, alpha: 1)
        case .blue:
            UIColor(red: 0.11, green: 0.38, blue: 0.70, alpha: 1)
        case .teal:
            UIColor(red: 0.05, green: 0.47, blue: 0.47, alpha: 1)
        case .burgundy:
            UIColor(red: 0.55, green: 0.10, blue: 0.21, alpha: 1)
        }
    }
}
