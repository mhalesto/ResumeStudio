import PDFKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
    let data: Data
    /// Breathing room after the final page. `contentMargins` on the SwiftUI shell
    /// cannot reach PDFKit's private scroll view, so the document otherwise ends
    /// hard against the floating app footer.
    var bottomClearance: CGFloat = 56

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        updateScrollClearance(in: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
            view.autoScales = true
        }
        // PDFKit rebuilds its internal document view after assigning a PDF.
        // Apply now and once more on the next run loop so both paths keep the gap.
        updateScrollClearance(in: view)
        DispatchQueue.main.async { updateScrollClearance(in: view) }
    }

    private func updateScrollClearance(in view: UIView) {
        guard let scrollView = descendantScrollView(in: view) else { return }
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
