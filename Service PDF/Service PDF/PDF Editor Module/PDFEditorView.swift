import SwiftUI
import PhotosUI
internal import PDFKit

struct PDFEditorView<ViewModel: PDFEditorViewModelProtocol>: View {
    // MARK: - Dependencies
    @ObservedObject var viewModel: ViewModel

    // MARK: - State
    @State private var isPresentingPicker = false
    @State private var isImporting = false
    @State private var isShowingPreview = false
    @State private var isShowingShare = false
    @State private var isAskingFileName = false
    @State private var fileName: String = ""
    @State private var showSourceDialog = false
    @State private var pendingSource: Source? = nil

    private enum Source {
        case photos
        case files
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 16) {
            addImagesButton

            selectionHeader

            actionButtons

            if viewModel.isLoading {
                ProgressView("Processing...")
                    .padding(.top, 8)
            }

            generatedCardOrPlaceholder

            Spacer()
        }
        .padding()
        .navigationTitle("PDF Editor")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Пустой якорь под заголовок, чтобы он прорисовывался сразу
                EmptyView()
            }
        }
        .alert(isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in }
        )) {
            Alert(
                title: Text("Error"),
                message: Text(viewModel.errorMessage ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $isShowingPreview) {
            if let data = viewModel.generatedPDF {
                PDFPreviewView(
                    source: .data(data),
                    displayMode: .singlePageContinuous,
                    autoScales: true,
                    displayDirection: .vertical,
                    minScaleFactor: 0.5,
                    maxScaleFactor: 5.0,
                    backgroundColor: .systemBackground
                )
            } else {
                Text("No PDF to preview")
                    .padding()
            }
        }
        .sheet(isPresented: $isShowingShare) {
            if let data = viewModel.generatedPDF {
                ShareSheet(items: [
                    ShareItem(payload: .data(
                        data,
                        suggestedFileName: "My PDF Doc.pdf",
                        contentType: .pdf
                    ))
                ])
            } else {
                Text("Nothing to share")
                    .padding()
            }
        }
        .sheet(isPresented: $isAskingFileName) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Save PDF As")
                        .font(.headline)

                    TextField("File name", text: $fileName)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .placeholder(when: fileName.isEmpty) {
                            Text("Enter file name (without extension)")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                    Text("The file will be saved into the app’s PDFs folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding()
                .navigationBarItems(
                    leading: Button("Cancel") {
                        isAskingFileName = false
                    },
                    trailing: Button("Save") {
                        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        isAskingFileName = false
                        viewModel.savePDF(fileName: trimmed)
                    }
                    .disabled(viewModel.generatedPDF == nil || viewModel.isLoading)
                )
            }
        }
    }

    // MARK: - Subviews

    private var addImagesButton: some View {
        Button {
            showSourceDialog = true
        } label: {
            HStack {
                Image(systemName: "plus.viewfinder")
                Text("Add Images")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .confirmationDialog("Add images from", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button {
                pendingSource = .photos
                isPresentingPicker = true
            } label: {
                Label("Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                pendingSource = .files
                isImporting = true
            } label: {
                Label("Files", systemImage: "folder")
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $isPresentingPicker) {
            // Photos
            PhotoPickerView(maxSelection: 20) { result in
                if !result.isEmpty {
                    viewModel.addImages(result)
                }
                pendingSource = nil
            }
        }
        .sheet(isPresented: $isImporting) {
            // Files
            DocumentPickerView(allowsMultipleSelection: true) { data in
                if !data.isEmpty {
                    viewModel.addImages(data)
                }
                pendingSource = nil
            }
        }
    }

    private var selectionHeader: some View {
        HStack {
            Text("Selected images: \(viewModel.selectedImages.count)")
                .font(.subheadline)
            Spacer()
            Button(role: .destructive) {
                viewModel.deleteGeneratedPDF()
            } label: {
                Text("Delete PDF")
            }
            .disabled(viewModel.generatedPDF == nil)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.generatePDF()
            }) {
                Label("Generate PDF", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedImages.isEmpty || viewModel.isLoading)
            
            Button(action: {
                fileName = ""
                isAskingFileName = true
            }) {
                Label("Save PDF", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.generatedPDF == nil || viewModel.isLoading)
            
            Button(action: {
                isShowingPreview = true
            }) {
                Label("Preview", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.generatedPDF == nil || viewModel.isLoading)
        }
    }

    private var generatedCardOrPlaceholder: some View {
        Group {
            if let data = viewModel.generatedPDF {
                VStack(spacing: 12) {
                    if let thumbData = viewModel.generatedThumbnail,
                       let uiImage = UIImage(data: thumbData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { isShowingPreview = true }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Generating preview…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 220)
                    }
                    
                    Text("PDF is ready")
                        .font(.headline)
                    Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        isShowingShare = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No PDF generated yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
}

// MARK: - Helpers

private extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
