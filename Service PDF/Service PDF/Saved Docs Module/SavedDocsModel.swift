//
//  SavedDocsModel.swift
//  Service PDF
//
//  Created by Василий Максимов on 31.10.2025.
//

import Foundation
import CoreData

// MARK: - View Model DTO
struct SavedDocItem: Identifiable, Equatable {
    // MARK: - Identity
    let id: NSManagedObjectID

    // MARK: - File
    let fileName: String          // Имя файла (с расширением .pdf)
    let displayTitle: String      // Текст для UI (без .pdf)

    // MARK: - Meta
    let createdAt: Date
    let size: Int64

    // MARK: - Media / Access
    let thumbnailData: Data?
    let bookmarkData: Data?
    
    // MARK: - Init
    init(entity: StoredPDF) {
        id = entity.objectID

        let name = entity.fileName ?? "Document.pdf"
        fileName = name

        if name.lowercased().hasSuffix(".pdf") {
            displayTitle = String(name.dropLast(4))
        } else {
            displayTitle = name
        }

        createdAt = entity.createdAt ?? Date()
        size = entity.size
        thumbnailData = entity.thumbnail
        bookmarkData = entity.bookmarkData
    }
}
