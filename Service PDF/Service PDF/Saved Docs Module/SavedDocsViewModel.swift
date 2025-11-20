//
//  SavedDocsViewModel.swift
//  Service PDF
//
//

import Foundation
import Combine
import CoreData
import UniformTypeIdentifiers
internal import PDFKit

// MARK: - Protocol

protocol SavedDocsViewModelProtocol: ObservableObject {
    var items: [SavedDocItem] { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func fetch()
    func cleanupFileAccesses()

    // Actions
    func delete(item: SavedDocItem)
    func addPDF(data: Data, fileName: String)
    func mergeAndAddPDF(source: SavedDocItem, target: SavedDocItem)
}

// MARK: - ViewModel

@MainActor
final class SavedDocsViewModel: SavedDocsViewModelProtocol {

    // MARK: - Published

    @Published private(set) var items: [SavedDocItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let viewContext: NSManagedObjectContext
    private let pdfService: PDFServiceProtocol

    // MARK: - Internal State

    private var cancellables = Set<AnyCancellable>()
    private var notificationsCancellable: AnyCancellable?
    private var accessedURLs: [URL] = []

    // MARK: - Init

    init(context: NSManagedObjectContext, pdfService: PDFServiceProtocol) {
        self.viewContext = context
        self.pdfService = pdfService

        notificationsCancellable = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetch()
            }
    }

    convenience init(context: NSManagedObjectContext) {
        self.init(context: context, pdfService: PDFService())
    }

    deinit {
        notificationsCancellable?.cancel()
        Task { @MainActor [accessedURLs] in
            for url in accessedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    // MARK: - Public API

    func fetch() {
        isLoading = true
        errorMessage = nil

        let request: NSFetchRequest<StoredPDF> = StoredPDF.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let result = try viewContext.fetch(request)
            items = result.map(SavedDocItem.init(entity:))
            isLoading = false
            prepareFileAccesses()
        } catch {
            isLoading = false
            errorMessage = (error as NSError).localizedDescription
            cleanupFileAccesses()
        }
    }

    func cleanupFileAccesses() {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
    }

    func delete(item: SavedDocItem) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if let bookmark = item.bookmarkData {
                    try await pdfService.deletePDF(bookmarkData: bookmark)
                }

                let objectID = item.id
                if let object = try? viewContext.existingObject(with: objectID) as? StoredPDF {
                    viewContext.delete(object)
                    try viewContext.save()
                }

                fetch()
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = "Failed to delete: \(error.localizedDescription)"
            }
        }
    }

    func addPDF(data: Data, fileName: String) {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil

            do {
                let url = try await pdfService.savePDF(
                    data: data,
                    fileName: fileName,
                    folderName: "PDFs"
                )

                let bookmark = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                let thumb = await pdfService.thumbnail(
                    for: data,
                    maxSize: CGSize(width: 240, height: 240)
                )

                let entity = StoredPDF(context: viewContext)
                entity.id = UUID()
                entity.fileName = url.lastPathComponent
                entity.size = Int64(data.count)
                entity.bookmarkData = bookmark
                entity.createdAt = Date()
                entity.updatedAt = Date()
                entity.thumbnail = thumb

                try viewContext.save()
                isLoading = false
                fetch()
            } catch {
                isLoading = false
                errorMessage = "Failed to add PDF: \(error.localizedDescription)"
            }
        }
    }

    func mergeAndAddPDF(source: SavedDocItem, target: SavedDocItem) {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil

            guard
                let data1 = pdfData(for: source),
                let data2 = pdfData(for: target)
            else {
                isLoading = false
                errorMessage = "Could not read PDF files for merge."
                return
            }

            do {
                let mergedData = try await pdfService.mergePDFData([data1, data2])
                let mergedName = "\(source.displayTitle)_\(target.displayTitle)_merged"
                addPDF(data: mergedData, fileName: mergedName)
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = "PDF merge failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Private

    private func prepareFileAccesses() {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()

        for item in items {
            guard let bookmark = item.bookmarkData else { continue }
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
        }
    }

    private func pdfData(for item: SavedDocItem) -> Data? {
        guard let bookmark = item.bookmarkData else { return nil }
        var isStale = false

        if let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return try? Data(contentsOf: url)
        }
        return nil
    }
}

