import SwiftUI
import UIKit

/// The trackable-links surface: every hosted résumé link, who opened it, and
/// for how long it was read. The list is the pipeline view; the payoff moments
/// arrive as notifications from `SmartLinkStore.refresh()`.
struct SmartLinksView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var smartLinks: SmartLinkStore
  @State private var isCreating = false

  private var accent: Color { store.document.accent.color }

  var body: some View {
    List {
      if smartLinks.links.isEmpty {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Text("Know when you're read")
              .font(Theme.display(28))
            Text("Send a link instead of an attachment. The moment a recruiter opens it you'll know — how many times, and for how long they actually read.")
              .font(.subheadline)
              .foregroundStyle(Theme.inkSoft)
            Text("The page tells viewers that opens are visible to you. No names, no locations — just honest reading time.")
              .font(.caption)
              .foregroundStyle(Theme.mutedInk)
            Button {
              isCreating = true
            } label: {
              Label("Create your first link", systemImage: "link.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .padding(.top, 6)
          }
          .padding(.vertical, 8)
        }
      } else {
        Section {
          HStack(spacing: 22) {
            linkStat(value: "\(smartLinks.activeCount)", label: "live")
            linkStat(value: "\(smartLinks.links.reduce(0) { $0 + $1.totalOpens })", label: "opens")
            linkStat(value: readingTime(smartLinks.links.reduce(0) { $0 + $1.totalSeconds }), label: "read")
            Spacer()
          }
          .padding(.vertical, 4)
        } footer: {
          if let error = smartLinks.lastRefreshError {
            Text(error)
          }
        }

        Section("Your links") {
          ForEach(smartLinks.links) { link in
            NavigationLink {
              SmartLinkDetailView(link: link)
            } label: {
              SmartLinkRow(link: link, accent: accent)
            }
          }
        }
      }
    }
    .navigationTitle("Trackable links")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          isCreating = true
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Create trackable link")
      }
    }
    .refreshable { await smartLinks.refresh(force: true) }
    .task { await smartLinks.refresh(force: true) }
    .sheet(isPresented: $isCreating) {
      NavigationStack { CreateSmartLinkSheet() }
    }
  }

  private func linkStat(value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(.title3.bold().monospacedDigit())
      Text(label).eyebrow().foregroundStyle(Theme.mutedInk)
    }
  }
}

struct SmartLinkRow: View {
  let link: SmartLink
  let accent: Color

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Circle()
        .fill(statusColor)
        .frame(width: 9, height: 9)
        .padding(.top, 5)
      VStack(alignment: .leading, spacing: 3) {
        Text(link.company.isBlank ? link.title : link.company)
          .font(.headline)
        Text(summary)
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
      }
      Spacer()
      if link.unseenOpens > 0 {
        Text("\(link.unseenOpens) new")
          .font(.caption2.bold())
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(accent, in: Capsule())
          .foregroundStyle(.white)
      }
    }
    .padding(.vertical, 2)
  }

  private var statusColor: Color {
    switch link.status {
    case .open: link.isActive ? .green : .orange
    case .expired: .orange
    case .revoked: .secondary
    }
  }

  private var summary: String {
    var parts: [String] = []
    if !link.isActive { parts.append(link.status == .revoked ? "Revoked" : "Expired") }
    parts.append("\(link.totalOpens) open\(link.totalOpens == 1 ? "" : "s")")
    if link.totalSeconds > 0 { parts.append("\(readingTime(link.totalSeconds)) read") }
    if let seen = link.lastSeenAt {
      parts.append("last \(seen.formatted(.relative(presentation: .named)))")
    }
    return parts.joined(separator: " · ")
  }
}

/// One link's full story: every visitor, opens, honest reading time, and the
/// controls that end it. Opening this screen acknowledges the activity.
struct SmartLinkDetailView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var smartLinks: SmartLinkStore
  @Environment(\.dismiss) private var dismiss
  let link: SmartLink

  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var confirmRevoke = false
  @State private var confirmDelete = false

  private var accent: Color { store.document.accent.color }
  private var current: SmartLink { smartLinks.links.first { $0.id == link.id } ?? link }
  /// Reconstructed from the token so links saved before the backend URL fix
  /// still share a URL that resolves.
  private var shareURL: URL { SmartLinkService.viewerURL(token: current.token) ?? current.url }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text(current.title).font(.headline)
          if !current.company.isBlank {
            Text("Sent to \(current.company)").font(.subheadline).foregroundStyle(Theme.inkSoft)
          }
          Text("\(current.status.title) · expires \(current.expiresAt.formatted(date: .abbreviated, time: .omitted))")
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
        }
        .padding(.vertical, 2)
        if current.isActive {
          ShareLink(item: shareURL) {
            Label("Share link", systemImage: "square.and.arrow.up")
          }
          Button {
            UIPasteboard.general.string = shareURL.absoluteString
          } label: {
            Label("Copy link", systemImage: "doc.on.doc")
          }
        }
      }

      Section {
        if current.views.isEmpty {
          Text("No opens yet. You'll get a notification the moment it happens.")
            .font(.subheadline)
            .foregroundStyle(Theme.mutedInk)
        }
        ForEach(current.views) { view in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: deviceIcon(view.viewer))
              .foregroundStyle(accent)
              .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
              Text(view.viewer).font(.subheadline.weight(.semibold))
              Text(viewSummary(view))
                .font(.caption)
                .foregroundStyle(Theme.mutedInk)
              if view.downloadedPDF {
                Label("Downloaded the PDF", systemImage: "arrow.down.circle.fill")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(accent)
              }
            }
          }
          .padding(.vertical, 2)
        }
      } header: {
        Text("Reading activity")
      } footer: {
        Text("Viewers are counted by device, never identified. Reading time only accrues while the page is actually visible.")
      }

      Section {
        if current.isActive {
          Button(role: .destructive) {
            confirmRevoke = true
          } label: {
            Label("Revoke link", systemImage: "xmark.circle")
          }
          .disabled(isWorking)
        }
        Button(role: .destructive) {
          confirmDelete = true
        } label: {
          Label("Delete link and its history", systemImage: "trash")
        }
        .disabled(isWorking)
      } footer: {
        if let errorMessage {
          Text(errorMessage).foregroundStyle(.orange)
        } else {
          Text("Revoking stops the link working immediately. Deleting also removes its reading history everywhere.")
        }
      }
    }
    .navigationTitle("Link activity")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { smartLinks.acknowledge(link.id) }
    .confirmationDialog("Revoke this link?", isPresented: $confirmRevoke, titleVisibility: .visible) {
      Button("Revoke link", role: .destructive) {
        Task {
          isWorking = true
          defer { isWorking = false }
          do { try await smartLinks.revoke(link.id) } catch { errorMessage = error.localizedDescription }
        }
      }
    } message: {
      Text("Anyone opening it will see that the résumé is no longer available.")
    }
    .confirmationDialog("Delete this link?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete link", role: .destructive) {
        Task {
          isWorking = true
          await smartLinks.delete(link.id)
          isWorking = false
          dismiss()
        }
      }
    } message: {
      Text("The hosted PDF and all reading history are removed.")
    }
  }

  private func viewSummary(_ view: SmartLinkView) -> String {
    var parts = ["\(view.opens) open\(view.opens == 1 ? "" : "s")"]
    if view.seconds > 0 { parts.append("\(readingTime(view.seconds)) read") }
    if let seen = view.lastSeenAt {
      parts.append("last \(seen.formatted(.relative(presentation: .named)))")
    }
    return parts.joined(separator: " · ")
  }

  private func deviceIcon(_ hint: String) -> String {
    if hint.contains("iPhone") || hint.contains("Android") { return "iphone" }
    if hint.contains("iPad") { return "ipad" }
    if hint.contains("Mac") { return "laptopcomputer" }
    if hint.contains("Windows") || hint.contains("Linux") { return "desktopcomputer" }
    return "eye"
  }
}

/// Publishes the current résumé behind a fresh trackable link.
struct CreateSmartLinkSheet: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var smartLinks: SmartLinkStore
  @EnvironmentObject private var purchases: PurchaseManager
  @Environment(\.dismiss) private var dismiss

  @State private var company = ""
  @State private var expiryDays = 30
  @State private var isPublishing = false
  @State private var errorMessage: String?
  @State private var canUpgrade = false
  @State private var publishedURL: URL?

  private var accent: Color { store.document.accent.color }
  private var allowance: Int { purchases.plan.smartLinkLimit }
  private var atCap: Bool { smartLinks.activeCount >= allowance }

  var body: some View {
    Form {
      if let publishedURL {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Label("Your link is live", systemImage: "checkmark.circle.fill")
              .font(.headline)
              .foregroundStyle(.green)
            Text(publishedURL.absoluteString)
              .font(.footnote.monospaced())
              .foregroundStyle(Theme.inkSoft)
              .textSelection(.enabled)
          }
          .padding(.vertical, 4)
          ShareLink(item: publishedURL) {
            Label("Share link", systemImage: "square.and.arrow.up")
          }
          Button {
            UIPasteboard.general.string = publishedURL.absoluteString
          } label: {
            Label("Copy link", systemImage: "doc.on.doc")
          }
        } footer: {
          Text("You'll be notified the first time it's opened. Activity lives in Trackable links.")
        }
      } else {
        Section {
          TextField("Company or recruiter (for your eyes only)", text: $company)
          Picker("Link expires in", selection: $expiryDays) {
            Text("30 days").tag(30)
            Text("60 days").tag(60)
            Text("90 days").tag(90)
          }
        } header: {
          Text("New trackable link")
        } footer: {
          Text("Hosts “\(store.document.suggestedFilename).pdf” behind a private link. The viewer page says opens are visible to you.")
        }

        Section {
          Button {
            publish()
          } label: {
            if isPublishing {
              HStack(spacing: 10) {
                ProgressView()
                Text("Publishing…")
              }
            } else {
              Label("Create link", systemImage: "link.badge.plus")
                .font(.headline)
            }
          }
          .disabled(isPublishing || atCap)
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            // The server enforces the plan (and rejects unverifiable purchases),
            // so its message is authoritative. Showing the client-side "X of Y
            // on your plan" line beside it contradicted the error — hide it
            // whenever the server has spoken.
            if let errorMessage {
              Text(errorMessage).foregroundStyle(.orange)
              if canUpgrade {
                Button("See plans") {
                  NotificationCenter.default.post(name: .presentPlans, object: nil)
                }
                .font(.footnote.weight(.semibold))
              }
            } else if atCap {
              Text(allowance == 1
                ? "Free hosts one active link — revoke the current one, or upgrade for more."
                : "Your plan supports \(allowance) active links. Revoke one to create another.")
              Button("See plans") {
                NotificationCenter.default.post(name: .presentPlans, object: nil)
              }
              .font(.footnote.weight(.semibold))
            } else {
              Text("\(smartLinks.activeCount) of \(allowance) active links on your plan.")
            }
          }
        }
      }
    }
    .navigationTitle("Trackable link")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(publishedURL == nil ? "Cancel" : "Done") { dismiss() }
      }
    }
  }

  private func publish() {
    isPublishing = true
    errorMessage = nil
    canUpgrade = false
    let document = store.document
    let company = company
    let expiry = Date(timeIntervalSinceNow: TimeInterval(expiryDays) * 86_400)
    Task {
      defer { isPublishing = false }
      do {
        let pdf = try ResumePDFRenderer.render(document: document)
        let pageImages = ResumePageRasterizer.images(fromPDF: pdf)
        let token = SmartLink.newToken()
        let hostedURL = try await SmartLinkService().publish(SmartLinkService.PublishRequest(
          token: token,
          title: document.suggestedFilename,
          company: company,
          expiresAt: expiry,
          pdfData: pdf,
          pageImages: pageImages
        ))
        // Prefer the token-derived URL so the saved link never inherits a
        // malformed origin from the backend response.
        let url = SmartLinkService.viewerURL(token: token) ?? hostedURL
        smartLinks.add(SmartLink(
          token: token,
          url: url,
          title: document.suggestedFilename,
          company: company,
          createdAt: Date(),
          expiresAt: expiry
        ))
        publishedURL = url
      } catch {
        errorMessage = error.localizedDescription
        canUpgrade = (error as? SmartLinkError)?.suggestsUpgrade ?? false
      }
    }
  }
}

private func readingTime(_ seconds: Int) -> String {
  if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
  return "\(seconds)s"
}

extension ResumeStudioPlan {
  /// Active hosted trackable links per plan. Enforced by the backend; shown
  /// here so the cap never surprises anyone.
  var smartLinkLimit: Int {
    switch self {
    case .free: 1
    case .go: 5
    case .pro: 25
    }
  }
}

#Preview {
  NavigationStack {
    SmartLinksView()
      .environmentObject(ResumeStore())
      .environmentObject(SmartLinkStore())
      .environmentObject(PurchaseManager.shared)
  }
}
