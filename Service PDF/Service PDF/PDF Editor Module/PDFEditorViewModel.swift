import Foundation
import Combine
import CoreData

protocol PDFEditorViewModelProtocol: ObservableObject {
    var selectedImages: [Data] { get }
    var generatedPDF: Data? { get }
    var generatedThumbnail: Data? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    
    func addImages(_ data: [Data])
    func generatePDF()
    func savePDF(fileName: String)
    func deleteGeneratedPDF()
}

@MainActor
final class PDFEditorViewModel: PDFEditorViewModelProtocol {
    
    @Published private(set) var selectedImages: [Data] = []
    @Published private(set) var generatedPDF: Data?
    @Published private(set) var generatedThumbnail: Data?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    
    private unowned let coordinator: CoordinatorProtocol
    private let pdfService: PDFServiceProtocol
    private let viewContext: NSManagedObjectContext
    
    private var cancellables = Set<AnyCancellable>()
    private var generateTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var thumbTask: Task<Void, Never>?
    
    init(coordinator: CoordinatorProtocol, pdfService: PDFServiceProtocol, context: NSManagedObjectContext) {
        self.coordinator = coordinator
        self.pdfService = pdfService
        self.viewContext = context
    }
    
    deinit {
        generateTask?.cancel()
        saveTask?.cancel()
        thumbTask?.cancel()
    }
    
    func addImages(_ data: [Data]) {
        selectedImages.append(contentsOf: data)
        generatedPDF = nil
        generatedThumbnail = nil
        errorMessage = nil
    }
    
    func generatePDF() {
        generateTask?.cancel()
        thumbTask?.cancel()
        
        generateTask = Task { [weak self] in
            guard let self else { return }
            guard !selectedImages.isEmpty else {
                self.errorMessage = "Please, add some images first."
                return
            }
            isLoading = true
            errorMessage = nil
            do {
                let pdfData = try await pdfService.createPDFData(
                    from: selectedImages,
                    pageSize: nil,
                    margins: .init(top: 36, left: 36, bottom: 36, right: 36),
                    landscape: false,
                    title: "My PDF Doc"
                )
                
                guard !Task.isCancelled else { return }
                self.generatedPDF = pdfData
                self.isLoading = false
                
                // Генерация превью первой страницы сразу после успешной генерации PDF
                self.thumbTask = Task { [weak self] in
                    guard let self else { return }
                    let thumb = await pdfService.thumbnail(for: pdfData, maxSize: CGSize(width: 240, height: 240))
                    guard !Task.isCancelled else { return }
                    self.generatedThumbnail = thumb
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = (error as NSError).localizedDescription
            }
        }
    }
    
    // Сохранение с заданным именем
    func savePDF(fileName: String) {
        saveTask?.cancel()
        
        saveTask = Task { [weak self] in
            guard let self else { return }
            guard let data = generatedPDF else {
                self.errorMessage = "Generate PDF before saving."
                return
            }
            
            isLoading = true
            errorMessage = nil
            
            do {
                // 1) Санитизируем имя файла
                let sanitized = Self.sanitizeFileName(fileName, defaultName: "My PDF Doc", enforcedExtension: "pdf")
                
                // 2) Сохраняем PDF и получаем URL (сервис внутри обеспечит уникальность имени при конфликте)
                let url = try await pdfService.savePDF(
                    data: data,
                    fileName: sanitized,
                    folderName: "PDFs"
                )
                
                // 3) Создаём bookmarkData (на будущее, хотя доступ только к внутренним файлам)
                let bookmark = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                
                // 4) Генерируем превью (png) первой страницы
                let thumb = await pdfService.thumbnail(for: data, maxSize: CGSize(width: 240, height: 240))
                
                // 5) Создаём запись в Core Data
                let entity = StoredPDF(context: viewContext)
                entity.id = UUID()
                entity.fileName = url.lastPathComponent
                entity.size = Int64(data.count)
                entity.bookmarkData = bookmark
                entity.createdAt = Date()
                entity.updatedAt = Date()
                entity.thumbnail = thumb
                
                try viewContext.save()
                
                guard !Task.isCancelled else { return }
                
                self.resetEditorState()
                
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = (error as NSError).localizedDescription
            }
        }
    }
    
    func deleteGeneratedPDF() {
        generatedPDF = nil
        generatedThumbnail = nil
    }
}

// MARK: - Helpers
private extension PDFEditorViewModel {
    static func sanitizeFileName(_ name: String, defaultName: String, enforcedExtension: String) -> String {
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = defaultName }
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        base = base.components(separatedBy: invalid).joined(separator: "_")
        let url = URL(fileURLWithPath: base)
        var stem = url.deletingPathExtension().lastPathComponent
        if stem.isEmpty { stem = defaultName }
        if stem.count > 100 { stem = String(stem.prefix(100)) }
        let ext = url.pathExtension.isEmpty ? enforcedExtension : url.pathExtension
        return "\(stem).\(ext)"
    }
    
    func resetEditorState() {
        self.selectedImages = []
        self.generatedPDF = nil
        self.generatedThumbnail = nil
        self.errorMessage = nil
    }
}
