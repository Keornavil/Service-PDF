
import SwiftUI
import Combine
import CoreData

// MARK: - Protocol

protocol CoordinatorProtocol: AnyObject {
    func navigate(to screen: AppCoordinator.Screen)
    func view(for screen: AppCoordinator.Screen) -> AnyView
}

// MARK: - AppCoordinator

final class AppCoordinator: ObservableObject, CoordinatorProtocol {
    // MARK: - Navigation State
    @Published var currentScreen: Screen = .welcome

    // MARK: - Screen Enum
    enum Screen {
        case welcome
        case main
    }

    // MARK: - Dependencies
    private let pdfService: PDFServiceProtocol
    private let persistence: PersistenceController
    private let viewContext: NSManagedObjectContext

    // MARK: - ViewModels
    private lazy var welcomeViewModel = WelcomeViewModel(coordinator: self)
    private lazy var editorViewModel = PDFEditorViewModel(
        coordinator: self,
        pdfService: pdfService,
        context: viewContext
    )
    private lazy var savedDocsViewModel = SavedDocsViewModel(context: viewContext)

    // MARK: - Init
    init(
        pdfService: PDFServiceProtocol = PDFService(),
        persistence: PersistenceController = .shared
    ) {
        self.pdfService = pdfService
        self.persistence = persistence
        self.viewContext = persistence.container.viewContext
    }

    // MARK: - Navigation
    func navigate(to screen: Screen) {
        withAnimation {
            currentScreen = screen
        }
    }

    // MARK: - View Factory
    @ViewBuilder
    private func makeView(for screen: Screen) -> some View {
        switch screen {
        case .welcome:
            WelcomeView(viewModel: welcomeViewModel)

        case .main:
            TabView {
                NavigationView {
                    PDFEditorView(viewModel: editorViewModel)
                        //.navigationTitle("PDF Editor")
                }
                .tabItem {
                    Label("Editor", systemImage: "doc.richtext")
                }

                NavigationView {
                    SavedDocsView(viewModel: savedDocsViewModel)
                        //.navigationTitle("Saved PDFs")
                }
                .tabItem {
                    Label("Saved", systemImage: "tray.full")
                }
            }
            .tint(.blue)
        }
    }

    // MARK: - Protocol requirement (type-erased)
    func view(for screen: Screen) -> AnyView {
        AnyView(makeView(for: screen))
    }
}
