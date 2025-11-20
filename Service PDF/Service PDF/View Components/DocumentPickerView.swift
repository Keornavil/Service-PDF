import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentPickerView: UIViewControllerRepresentable {
    let allowsMultipleSelection: Bool
    let completion: ([Data]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var supportedTypes: [UTType] = [
            .image,
            .png,
            .jpeg,
            .tiff,
            .gif,
            .bmp
        ]
        if let heic = UTType("public.heic") {
            supportedTypes.append(heic)
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes.uniqued(), asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: ([Data]) -> Void

        init(completion: @escaping ([Data]) -> Void) {
            self.completion = completion
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion([])
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            var collected: [Data] = []
            let group = DispatchGroup()

            for url in urls {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let needsAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if needsAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    if let data = try? Data(contentsOf: url) {
                        collected.append(data)
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.completion(collected)
            }
        }
    }
}

private extension Array where Element == UTType {
    func uniqued() -> [UTType] {
        var seen = Set<String>()
        var result: [UTType] = []
        for t in self {
            if !seen.contains(t.identifier) {
                seen.insert(t.identifier)
                result.append(t)
            }
        }
        return result
    }
}
