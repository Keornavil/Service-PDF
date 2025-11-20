//
//  PDFEditorModel.swift
//  Swift PDF
//
//  Created by Василий Максимов on 25.10.2025.
//

import Foundation

public struct Page: Identifiable, Equatable {
    public let id: UUID
    public let data: Data
    public let sourseFileName: String?

    public init(id: UUID = UUID(), data: Data, sourseFileName: String? = nil) {
        self.id = id
        self.data = data
        self.sourseFileName = sourseFileName
    }
}

public struct PDFSize {
    public let width: Double
    public let height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
public struct PDFMargins {
    public let top: Double
    public let left: Double
    public let bottom: Double
    public let right: Double
    public init(top: Double = 36, left: Double = 36, bottom: Double = 36, right: Double = 36) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}
