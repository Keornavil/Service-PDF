//
//  Service_PDFApp.swift
//  Service PDF
//
//  Created by Василий Максимов on 30.10.2025.
//

import SwiftUI
import CoreData

@main
struct Service_PDFApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                coordinator.view(for: coordinator.currentScreen)
            }
        }
    }
}
