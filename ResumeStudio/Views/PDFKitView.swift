import PDFKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
    let data: Data
    /// Breathing room after the final page. `contentMargins` on the SwiftUI shell
    /// cannot reach PDFKit's private scroll view, so the document otherwise ends
    /// hard against the floating app footer.
    var bottomClearance: CGFloat = 56

    /// Reports a double tap as the line of text under it, the text that follows it
    /// on the same page, and how far down the page it landed — enough for the
    /// preview to work out which part of the résumé was hit. Leaving this `nil`
    /// keeps PDFKit's own double-tap zoom.
    var onDoubleTap:
        ((_ line: String, _ preceding: String, _ following: String, _ relativeY: CGFloat,
            _ pageIndex: Int) -> Void)?

    /// What colour a double tap glows in. The résumé's own accent, so the
    /// highlight looks like part of the document rather than a system selection.
    var highlight: Color = .accentColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = QuickEditPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        updateScrollClearance(in: view)
        if onDoubleTap != nil {
            let recognizer = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleDoubleTap(_:))
            )
            recognizer.numberOfTapsRequired = 2
            recognizer.delegate = context.coordinator
            // Editing must not swallow the touches PDFKit uses to scroll and zoom.
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            view.addGestureRecognizer(recognizer)
            view.quickEditTap = recognizer
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedData != data {
            context.coordinator.loadedData = data
            // Where the reader is, so a re-render does not send them back to the
            // top of the résumé to find the paragraph they just edited.
            let anchor = visibleAnchor(in: view)
            view.document = PDFDocument(data: data)
            view.autoScales = true
            // A new document means a new internal view tree, and new gesture
            // recognisers to claim.
            (view as? QuickEditPDFView)?.resetGestureClaims()
            if let anchor { restore(anchor, in: view) }
        }
        // PDFKit rebuilds its internal document view after assigning a PDF.
        // Apply now and once more on the next run loop so both paths keep the gap.
        updateScrollClearance(in: view)
        DispatchQueue.main.async { updateScrollClearance(in: view) }
    }

    /// The page and point currently at the top of the view.
    private func visibleAnchor(in view: PDFView) -> (index: Int, point: CGPoint)? {
        guard let destination = view.currentDestination,
            let page = destination.page,
            let index = page.document?.index(for: page)
        else { return nil }
        return (index, destination.point)
    }

    /// Puts the reader back where they were. Deferred a run loop because PDFKit
    /// lays the new document out asynchronously, and scrolling before that lands
    /// on the wrong offset. An edit can repaginate, so a page that no longer
    /// exists simply leaves the preview at the top.
    private func restore(_ anchor: (index: Int, point: CGPoint), in view: PDFView) {
        DispatchQueue.main.async {
            guard let page = view.document?.page(at: anchor.index) else { return }
            view.go(to: PDFDestination(page: page, at: anchor.point))
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PDFKitView
        /// The bytes last handed to PDFKit. `PDFDocument.dataRepresentation()`
        /// re-serialises the document on every call rather than returning what
        /// was loaded, so comparing against it reported a change on every
        /// SwiftUI update — and reassigning the document scrolls the preview
        /// back to page one. That is what made double-tapping anything on page
        /// two jump to the top before the edit sheet appeared.
        var loadedData: Data?

        init(_ parent: PDFKitView) { self.parent = parent }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let pdfView = recognizer.view as? PDFView else { return }
            let point = recognizer.location(in: pdfView)
            guard let page = pdfView.page(for: point, nearest: true) else { return }
            let pagePoint = pdfView.convert(point, to: page)
            let bounds = page.bounds(for: .mediaBox)
            // PDF pages measure upward from the bottom-left; flip so 0 is the top,
            // which is how anyone describing a résumé thinks about it.
            let relativeY = bounds.height > 0 ? 1 - (pagePoint.y / bounds.height) : 0
            let index = page.document?.index(for: page) ?? 0
            // Everything printed under the finger, down to the foot of the page.
            // A section heading says which section, and this says which entry of
            // it is actually on the page being looked at.
            let below = CGRect(
                x: bounds.minX, y: bounds.minY,
                width: bounds.width, height: max(0, pagePoint.y - bounds.minY))
            // Everything printed above the finger. The last section heading in it
            // is the section being pointed at, which is what tells a referee's
            // employer apart from the same company listed as a role.
            let above = CGRect(
                x: bounds.minX, y: pagePoint.y,
                width: bounds.width, height: max(0, bounds.maxY - pagePoint.y))
            let hit = text(at: pagePoint, on: page, within: bounds)
            // Light up what was hit before the sheet covers it, so the tap reads
            // as landing on that line rather than as the page simply moving.
            if let rect = hit.rect {
                (pdfView as? QuickEditPDFView)?.flashHighlight(
                    pdfView.convert(rect, from: page),
                    color: UIColor(parent.highlight))
            }
            parent.onDoubleTap?(
                hit.text,
                page.selection(for: above)?.string ?? "",
                page.selection(for: below)?.string ?? "",
                min(max(relativeY, 0), 1), index)
        }

        /// A finger is far blunter than a line of 9pt type. Landing in the leading
        /// between two lines returns nothing at all, which read as "there is
        /// nothing here" and was most of what felt unreliable about the gesture —
        /// so a miss widens to a band across the page before giving up.
        ///
        /// The bounds come back with the text because whatever was read is also
        /// what gets highlighted.
        private func text(
            at point: CGPoint, on page: PDFPage, within bounds: CGRect
        ) -> (text: String, rect: CGRect?) {
            if let line = page.selectionForLine(at: point), let string = line.string,
                !string.isBlank
            {
                return (string, line.bounds(for: page))
            }
            // Widen around the finger, but only around it. Sweeping the full width
            // of the page let a two-column layout answer with whatever happened to
            // sit at the same height in the other column — which is how tapping
            // the portrait came back with a skill printed beside it.
            let reach: CGFloat = 132
            let left = max(bounds.minX, point.x - reach)
            let right = min(bounds.maxX, point.x + reach)
            let band = CGRect(
                x: left, y: point.y - 9, width: max(0, right - left), height: 18)
            guard let fallback = page.selection(for: band), let string = fallback.string else {
                return ("", nil)
            }
            return (string, fallback.bounds(for: page))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }

    private func updateScrollClearance(in view: UIView) {
        guard let scrollView = descendantScrollView(in: view) else { return }
        // Writing an inset mid-scroll interrupts deceleration, and this runs on
        // every SwiftUI update, so only touch it when it is actually wrong.
        guard scrollView.contentInset.bottom != bottomClearance else { return }
        var inset = scrollView.contentInset
        inset.bottom = bottomClearance
        scrollView.contentInset = inset
        var indicatorInset = scrollView.verticalScrollIndicatorInsets
        indicatorInset.bottom = bottomClearance
        scrollView.verticalScrollIndicatorInsets = indicatorInset
    }

    private func descendantScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = descendantScrollView(in: subview) { return scrollView }
        }
        return nil
    }
}

/// PDFKit installs its own double tap to zoom, and builds it lazily — after the
/// document view exists, and again whenever a new document is assigned. Claiming
/// it once left later taps landing on a fresh, unclaimed recogniser, which is
/// what made the gesture feel like it worked only sometimes. Re-claiming on
/// layout catches every rebuild; a double tap edits, and pinch still zooms.
final class QuickEditPDFView: PDFView {
    weak var quickEditTap: UITapGestureRecognizer?
    /// Held weakly, so recognisers PDFKit has thrown away drop out by themselves
    /// and a rebuilt page view is treated as the new thing it is.
    private let claimed = NSHashTable<UITapGestureRecognizer>.weakObjects()
    private weak var highlight: UIView?

    func resetGestureClaims() { claimed.removeAllObjects() }

    /// Blooms a soft panel over the tapped line and fades it out under the
    /// rising sheet. It sits in view coordinates rather than on the page, which
    /// is fine for the second it lives — a double tap opens the editor
    /// immediately, so there is nothing to scroll it out of place.
    func flashHighlight(_ rect: CGRect, color: UIColor) {
        guard rect.width > 1, rect.height > 1 else { return }
        highlight?.removeFromSuperview()
        let panel = UIView(frame: rect.insetBy(dx: -7, dy: -5))
        panel.backgroundColor = color.withAlphaComponent(0.18)
        panel.layer.borderColor = color.withAlphaComponent(0.42).cgColor
        panel.layer.borderWidth = 1
        panel.layer.cornerRadius = 7
        panel.layer.cornerCurve = .continuous
        panel.isUserInteractionEnabled = false
        panel.alpha = 0
        panel.transform = CGAffineTransform(scaleX: 0.94, y: 0.82)
        addSubview(panel)
        highlight = panel
        UIView.animate(
            withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0, options: [.allowUserInteraction]
        ) {
            panel.alpha = 1
            panel.transform = .identity
        } completion: { _ in
            UIView.animate(
                withDuration: 0.45, delay: 0.3, options: [.allowUserInteraction]
            ) {
                panel.alpha = 0
            } completion: { _ in
                panel.removeFromSuperview()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Every layout, not just the first. PDFKit builds a page view — and its
        // own double tap to zoom — as each page is scrolled into range, so
        // stopping once something had been claimed left every page after the
        // first zooming instead of editing.
        claimDoubleTaps(in: self)
    }

    private func claimDoubleTaps(in view: UIView) {
        guard let quickEditTap else { return }
        for recognizer in view.gestureRecognizers ?? [] where recognizer !== quickEditTap {
            guard let tap = recognizer as? UITapGestureRecognizer,
                tap.numberOfTapsRequired == 2,
                !claimed.contains(tap)
            else { continue }
            claimed.add(tap)
            tap.require(toFail: quickEditTap)
        }
        for subview in view.subviews { claimDoubleTaps(in: subview) }
    }
}
