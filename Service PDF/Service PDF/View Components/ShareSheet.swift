import SwiftUI
import UniformTypeIdentifiers

struct ShareItem {
    enum Payload {
        case data(Data, suggestedFileName: String, contentType: UTType)
        case url(URL)
        case any(Any) // запасной вариант, если нужно передать произвольный тип
    }
    let payload: Payload
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [ShareItem]
    var activities: [UIActivity]? = nil
    var completion: UIActivityViewController.CompletionWithItemsHandler? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityItems = items.map { item -> Any in
            switch item.payload {
            case .url(let url):
                return url
            case .data(let data, let suggestedFileName, let contentType):
                // Оборачиваем Data в файл на лету через временный URL, чтобы корректно передавалось имя и type
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(contentType.preferredFilenameExtension ?? "pdf")
                do {
                    try data.write(to: tempURL, options: .atomic)
                    // Переименуем, если пользователь указал имя
                    let finalURL = tempURL.deletingLastPathComponent().appendingPathComponent(suggestedFileName)
                    try? FileManager.default.removeItem(at: finalURL)
                    try? FileManager.default.moveItem(at: tempURL, to: finalURL)
                    return finalURL
                } catch {
                    // В случае ошибки — fallback: отдаём как есть Data
                    return data
                }
            case .any(let any):
                return any
            }
        }
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: activities)
        controller.completionWithItemsHandler = completion
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
