import PDFKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
            view.autoScales = true
        }
    }
}
