//
//  WelcomeViewModel.swift
//  Service PDF
//
//  Created by Василий Максимов on 19.10.2025.
//

import Foundation
import Combine

// MARK: - Protocol
protocol WelcomeViewModelProtocol: ObservableObject {
    func start()
}

// MARK: - ViewModel
final class WelcomeViewModel: WelcomeViewModelProtocol {
    // MARK: - Dependencies
    private unowned let coordinator: CoordinatorProtocol
    
    // MARK: - Init
    init(coordinator: CoordinatorProtocol) {
        self.coordinator = coordinator
    }
    
    // MARK: - Public API
    func start() {
        coordinator.navigate(to: .main)
    }
}
