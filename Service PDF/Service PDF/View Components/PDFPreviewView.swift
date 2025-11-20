import SwiftUI
internal import PDFKit

struct PDFPreviewView: View {
    enum Source {
        case data(Data)
        case url(URL)
    }
    
    let source: Source
    var displayMode: PDFDisplayMode = .singlePageContinuous
    var autoScales: Bool = true
    var displayDirection: PDFDisplayDirection = .vertical
    var minScaleFactor: CGFloat = 0.5
    var maxScaleFactor: CGFloat = 5.0
    var backgroundColor: UIColor = .systemBackground
    
    var body: some View {
        PDFKitContainer(
            source: source,
            displayMode: displayMode,
            autoScales: autoScales,
            displayDirection: displayDirection,
            minScaleFactor: minScaleFactor,
            maxScaleFactor: maxScaleFactor,
            backgroundColor: backgroundColor
        )
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct PDFKitContainer: UIViewRepresentable {
    let source: PDFPreviewView.Source
    let displayMode: PDFDisplayMode
    let autoScales: Bool
    let displayDirection: PDFDisplayDirection
    let minScaleFactor: CGFloat
    let maxScaleFactor: CGFloat
    let backgroundColor: UIColor
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = displayMode
        pdfView.displayDirection = displayDirection
        pdfView.autoScales = autoScales
        pdfView.minScaleFactor = minScaleFactor
        pdfView.maxScaleFactor = maxScaleFactor
        pdfView.backgroundColor = backgroundColor
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.displaysPageBreaks = true
        pdfView.document = makeDocument(from: source)
        pdfView.goToFirstPage(nil)
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Если источник изменился, обновим документ
        let newDocument = makeDocument(from: source)
        if pdfView.document != newDocument {
            pdfView.document = newDocument
            pdfView.goToFirstPage(nil)
        }
        pdfView.displayMode = displayMode
        pdfView.displayDirection = displayDirection
        pdfView.autoScales = autoScales
        pdfView.minScaleFactor = minScaleFactor
        pdfView.maxScaleFactor = maxScaleFactor
        pdfView.backgroundColor = backgroundColor
    }
    
    private func makeDocument(from source: PDFPreviewView.Source) -> PDFDocument? {
        switch source {
        case .data(let data):
            return PDFDocument(data: data)
        case .url(let url):
            return PDFDocument(url: url)
        }
    }
}
