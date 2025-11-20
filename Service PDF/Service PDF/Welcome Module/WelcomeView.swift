//
//  WelcomeView.swift
//  Service PDF
//
//  Created by Василий Максимов on 18.10.2025.
//

import SwiftUI

struct WelcomeView<ViewModel: WelcomeViewModelProtocol>: View {
    // MARK: - Dependencies
    @ObservedObject var viewModel: ViewModel

    // MARK: - Body
    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to PDFForge")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Create, edit and manage PDF documents easily!")
                .multilineTextAlignment(.center)
                .padding()

            Button("Get Started") {
                viewModel.start()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
