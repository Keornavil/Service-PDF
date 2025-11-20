//
//  PDFService.swift
//  Service PDF
//
//

import Foundation
internal import PDFKit

// MARK: - Protocol
public protocol PDFServiceProtocol {
    func createPDFData(
        from imagesData: [Data],
        pageSize: CGSize?,
        margins: PDFMargins?,
        landscape: Bool,
        title: String?
    ) async throws -> Data

    func createPDFData(
        from pages: [Page],
        pageSize: CGSize?,
        margins: PDFMargins?,
        landscape: Bool,
        title: String?
    ) async throws -> Data

    func savePDF(
        data: Data,
        fileName: String,
        folderName: String
    ) async throws -> URL

    func thumbnail(for data: Data, maxSize: CGSize) async -> Data?

    func mergePDFData(_ pdfs: [Data]) async throws -> Data
    func mergePDFs(urls: [URL], outputFileName: String, folderName: String) async throws -> URL

    func deletePDF(at url: URL) async throws
    func deletePDF(bookmarkData: Data) async throws
}

// MARK: - Service
public final class PDFService: PDFServiceProtocol {
    // MARK: - Dependencies
    private let fileManager: FileManager
    
    // MARK: - Init
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }
    
    // MARK: - Create PDF
    public func createPDFData(
        from imagesData: [Data],
        pageSize: CGSize? = nil,
        margins: PDFMargins? = nil,
        landscape: Bool = false,
        title: String? = nil
    ) async throws -> Data {
        let resolvedMargins = margins ?? PDFMargins()
        return try await generatePDF(
            imagesData: imagesData,
            pageSize: pageSize,
            margins: resolvedMargins,
            landscape: landscape,
            title: title
        )
    }
    
    public func createPDFData(
        from pages: [Page],
        pageSize: CGSize? = nil,
        margins: PDFMargins? = nil,
        landscape: Bool = false,
        title: String? = nil
    ) async throws -> Data {
        let dataArray = pages.map { $0.data }
        let resolvedMargins = margins ?? PDFMargins()
        return try await generatePDF(
            imagesData: dataArray,
            pageSize: pageSize,
            margins: resolvedMargins,
            landscape: landscape,
            title: title
        )
    }
    
    // MARK: - Save
    public func savePDF(
        data: Data,
        fileName: String,
        folderName: String = "PDFs"
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let folder = try self.createDocumentsSubfolder(named: folderName)
                    let sanitizedName = self.sanitizeFileName(fileName)
                    let baseNameNoExt = URL(fileURLWithPath: sanitizedName)
                        .deletingPathExtension()
                        .lastPathComponent
                    let uniqueURL = try self.uniqueFileURL(
                        baseFolder: folder,
                        baseName: baseNameNoExt,
                        ext: "pdf"
                    )
                    try data.write(to: uniqueURL, options: .atomic)
                    continuation.resume(returning: uniqueURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Thumbnail
    public func thumbnail(for data: Data, maxSize: CGSize) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard
                    let pdfDoc = PDFKit.PDFDocument(data: data),
                    let firstPage = pdfDoc.page(at: 0)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = firstPage.thumbnail(of: maxSize, for: .cropBox)
                continuation.resume(returning: image.pngData())
            }
        }
    }
    
    // MARK: - Merge
    public func mergePDFData(_ pdfs: [Data]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let merged = PDFDocument()
                var pageIndex = 0

                for data in pdfs {
                    guard let doc = PDFDocument(data: data) else { continue }
                    for i in 0..<doc.pageCount {
                        if let page = doc.page(at: i) {
                            merged.insert(page, at: pageIndex)
                            pageIndex += 1
                        }
                    }
                }

                guard let result = merged.dataRepresentation() else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "PDFService",
                            code: -101,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create merged PDF data"]
                        )
                    )
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    public func mergePDFs(urls: [URL], outputFileName: String, folderName: String) async throws -> URL {
        let datas: [Data] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: [Data] = []
                result.reserveCapacity(urls.count)
                for url in urls {
                    let needsAccess = url.startAccessingSecurityScopedResource()
                    defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        result.append(data)
                    }
                }
                continuation.resume(returning: result)
            }
        }

        let mergedData = try await mergePDFData(datas)

        let savedURL = try await savePDF(
            data: mergedData,
            fileName: outputFileName,
            folderName: folderName
        )
        return savedURL
    }

    // MARK: - Delete
    public func deletePDF(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let needsAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if needsAccess { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    if self.fileManager.fileExists(atPath: url.path) {
                        try self.fileManager.removeItem(at: url)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func deletePDF(bookmarkData: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var isStale = false
                do {
                    let url = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: [.withoutUI, .withoutMounting],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    let needsAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if needsAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    if self.fileManager.fileExists(atPath: url.path) {
                        try self.fileManager.removeItem(at: url)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Internal PDF Generation
    private func generatePDF(
        imagesData: [Data],
        pageSize: CGSize?,
        margins: PDFMargins,
        landscape: Bool,
        title: String?
    ) async throws -> Data {
        guard !imagesData.isEmpty else {
            throw PDFError.emptyImages
        }
        
        for (index, data) in imagesData.enumerated() {
            if UIImage(data: data) == nil {
                throw PDFError.invalidImageData(index: index)
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var targetSize = pageSize ?? CGSize(width: 595.2, height: 841.8) // A4 @72dpi
                if landscape {
                    targetSize = CGSize(width: targetSize.height, height: targetSize.width)
                }
                
                let contentRect = CGRect(
                    x: CGFloat(margins.left),
                    y: CGFloat(margins.top),
                    width: max(0, targetSize.width - CGFloat(margins.left + margins.right)),
                    height: max(0, targetSize.height - CGFloat(margins.top + margins.bottom))
                )
                
                let format = UIGraphicsPDFRendererFormat()
                if let title, !title.isEmpty {
                    format.documentInfo = [
                        kCGPDFContextTitle as String: title,
                        kCGPDFContextCreator as String: "Swift PDF"
                    ]
                } else {
                    format.documentInfo = [
                        kCGPDFContextCreator as String: "Swift PDF"
                    ]
                }
                
                let renderer = UIGraphicsPDFRenderer(
                    bounds: CGRect(origin: .zero, size: targetSize),
                    format: format
                )
                
                let pdfData = renderer.pdfData { ctx in
                    for imageData in imagesData {
                        ctx.beginPage()
                        if let image = UIImage(data: imageData) {
                            let aspect = min(
                                contentRect.width / image.size.width,
                                contentRect.height / image.size.height
                            )
                            let scaledSize = CGSize(
                                width: image.size.width * aspect,
                                height: image.size.height * aspect
                            )
                            let x = contentRect.minX + (contentRect.width - scaledSize.width) / 2
                            let y = contentRect.minY + (contentRect.height - scaledSize.height) / 2
                            
                            image.draw(in: CGRect(origin: CGPoint(x: x, y: y), size: scaledSize))
                        } else {
                            assertionFailure("Unexpected invalid image after pre-validation.")
                        }
                    }
                }
                
                continuation.resume(returning: pdfData)
            }
        }
    }
    
    // MARK: - File System Helpers
    private func createDocumentsSubfolder(named name: String) throws -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent(name, isDirectory: true)
        
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.illegalCharacters)
            .union(.controlCharacters)
        let sanitized = name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Document" : sanitized
    }
    
    private func uniqueFileURL(baseFolder: URL, baseName: String, ext: String) throws -> URL {
        var candidate = baseFolder.appendingPathComponent("\(baseName).\(ext)")
        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = baseFolder.appendingPathComponent("\(baseName) (\(suffix)).\(ext)")
            suffix += 1
        }
        return candidate
    }

    // MARK: - Errors
    public enum PDFError: Error, LocalizedError, Equatable {
        case emptyImages
        case invalidImageData(index: Int)
        
        public var errorDescription: String? {
            switch self {
            case .emptyImages:
                return "Список изображений пуст."
            case .invalidImageData(let index):
                return "Невозможно декодировать изображение с индексом \(index)."
            }
        }
    }
}
