import Foundation
import PhotosUI
import SwiftUI

struct PhotoPickerView: UIViewControllerRepresentable {
    let maxSelection: Int
    let completion: ([Data]) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = maxSelection
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        
        private let completion: ([Data]) -> Void
        private let preferredTypeIdentifiers: [String] = [
            "public.heic",
            "public.png",
            "public.jpeg",
            "public.tiff",
            "com.compuserve.gif",
            "com.microsoft.bmp",
            "org.webmproject.webp"
        ]
        
        init(completion: @escaping ([Data]) -> Void) {
            self.completion = completion
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            Task { @MainActor in
                guard !results.isEmpty else {
                    picker.dismiss(animated: true)
                    completion([])
                    return
                }
                let collected = await loadAll(results: results)
                picker.dismiss(animated: true)
                completion(collected)
            }
        }
        
        // MARK: - Async loaders
        
        private func loadAll(results: [PHPickerResult]) async -> [Data] {
            var output = Array<Data?>(repeating: nil, count: results.count)
            
            await withTaskGroup(of: (Int, Data?).self) { group in
                for (index, result) in results.enumerated() {
                    group.addTask {
                        let data = await self.loadData(for: result.itemProvider)
                        return (index, data)
                    }
                }
                
                for await (index, data) in group {
                    output[index] = data
                }
            }
            return output.compactMap { $0 }
        }
        
        private func loadData(for provider: NSItemProvider) async -> Data? {
            for typeId in preferredTypeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeId) {
                if let data = try? await loadDataRepresentation(provider: provider, typeIdentifier: typeId) {
                    return data
                }
            }
            if let image = try? await loadUIImage(provider: provider) {
                let data: Data?
                if imageHasAlpha(image) {
                    data = image.pngData()
                } else {
                    data = image.jpegData(compressionQuality: 0.9)
                }
                return data
            }
            return nil
        }
        
        // MARK: - Bridges to async
        
        private func loadDataRepresentation(provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: NSError(domain: "PhotoPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data for \(typeIdentifier)"]))
                    }
                }
            }
        }
        
        private func loadUIImage(provider: NSItemProvider) async throws -> UIImage {
            try await withCheckedThrowingContinuation { continuation in
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { object, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let image = object as? UIImage else {
                            continuation.resume(throwing: NSError(domain: "PhotoPicker", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode UIImage"]))
                            return
                        }
                        continuation.resume(returning: image)
                    }
                } else {
                    continuation.resume(throwing: NSError(domain: "PhotoPicker", code: -3, userInfo: [NSLocalizedDescriptionKey: "Provider can't load UIImage"]))
                }
            }
        }
    }
}

// MARK: - Helpers
private func imageHasAlpha(_ image: UIImage) -> Bool {
    guard let cgImage = image.cgImage else { return false }
    switch cgImage.alphaInfo {
    case .first, .last, .premultipliedFirst, .premultipliedLast:
        return true
    default:
        return false
    }
}
