//
//  SavedDocsView.swift
//  Service PDF
//
//  Created by Василий Максимов on 31.10.2025.
//

import SwiftUI
internal import PDFKit
import UniformTypeIdentifiers

struct SavedDocsView<ViewModel: SavedDocsViewModelProtocol>: View {
    // MARK: - Dependencies
    @ObservedObject var viewModel: ViewModel

    // MARK: - State
    @State private var isShowingPreview: Bool = false
    @State private var previewURL: URL? = nil

    @State private var mergingSourceID: SavedDocItem.ID? = nil
    @State private var isMerging: Bool = false
    @State private var selectedForShare: SavedDocItem? = nil
    @State private var confirmDelete: SavedDocItem? = nil

    // MARK: - Layout
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    // MARK: - Body
    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(message: error)
            } else if viewModel.items.isEmpty {
                emptyView
            } else {
                contentGrid
            }
        }
        .navigationTitle("Saved Docs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.fetch()
        }
        .onDisappear {
            viewModel.cleanupFileAccesses()
        }
        .sheet(isPresented: $isShowingPreview, onDismiss: {
            previewURL = nil
        }) {
            PDFPreviewOrErrorView(url: previewURL)
        }
        .sheet(item: $selectedForShare) { item in
            ShareSheetWrapper(item: item)
        }
        .alert(item: $confirmDelete) { item in
            Alert(
                title: Text("Delete PDF?"),
                message: Text("This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel.delete(item: item)
                },
                secondaryButton: .cancel()
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    withAnimation {
                        isMerging = false
                        mergingSourceID = nil
                    }
                }
                .opacity(isMerging ? 1 : 0)
                .disabled(!isMerging)
                .accessibilityHidden(!isMerging)
            }
            ToolbarItem(placement: .principal) {
                Text("Select second PDF to merge")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .opacity(isMerging ? 1 : 0)
                    .accessibilityHidden(!isMerging)
            }
        }
    }

    // MARK: - Subviews
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading documents…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") {
                viewModel.fetch()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No saved PDFs yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var contentGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.items) { item in
                    ZStack {
                        SavedDocCard(
                            item: item,
                            isMergeSource: mergingSourceID == item.id,
                            isSelectingMergeTarget: isMerging && mergingSourceID != item.id
                        )
                        .contentShape(Rectangle())

                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 3)
                            .padding(2)
                            .opacity(isMerging && mergingSourceID == item.id ? 1 : 0)
                            .allowsHitTesting(false)

                        Button {
                            if let sourceID = mergingSourceID,
                               let source = viewModel.items.first(where: { $0.id == sourceID }) {
                                let target = item
                                viewModel.mergeAndAddPDF(source: source, target: target)
                                withAnimation {
                                    isMerging = false
                                    mergingSourceID = nil
                                }
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.15))
                                .overlay(
                                    Image(systemName: "plus.square.on.square")
                                        .font(.system(size: 36))
                                        .foregroundColor(.blue)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(isMerging && mergingSourceID != item.id ? 1 : 0)
                        .allowsHitTesting(isMerging && mergingSourceID != item.id)
                    }
                    .onTapGesture {
                        handleTap(on: item)
                    }
                    .contextMenu {
                        contextMenu(for: item)
                    }
                }
            }
            .padding()
        }
    }

    private func contextMenu(for item: SavedDocItem) -> some View {
        Group {
            Button {
                selectedForShare = item
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                confirmDelete = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                withAnimation {
                    mergingSourceID = item.id
                    isMerging = true
                }
            } label: {
                Label("Merge…", systemImage: "square.stack.3d.down.right")
            }
        }
    }

    // MARK: - Actions
    private func handleTap(on item: SavedDocItem) {
        guard !isMerging else { return }

        if let bookmark = item.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                previewURL = url
            } else {
                previewURL = nil
            }
        } else {
            previewURL = nil
        }
        isShowingPreview = true
    }
}

// MARK: - Private Views

private struct PDFPreviewOrErrorView: View {
    let url: URL?

    var body: some View {
        if let url {
            PDFPreviewView(
                source: .url(url),
                displayMode: .singlePageContinuous,
                autoScales: true,
                displayDirection: .vertical,
                minScaleFactor: 0.5,
                maxScaleFactor: 5.0,
                backgroundColor: .systemBackground
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Could not open PDF file.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

private struct ShareSheetWrapper: View {
    let item: SavedDocItem

    var body: some View {
        if
            let url = urlForBookmark(item.bookmarkData),
            let data = try? Data(contentsOf: url)
        {
            ShareSheet(items: [
                ShareItem(payload: .data(data, suggestedFileName: item.fileName, contentType: .pdf))
            ])
        } else {
            Text("Could not prepare file for sharing.")
                .padding()
        }
    }
}

private func urlForBookmark(_ data: Data?) -> URL? {
    guard let data else { return nil }
    var isStale = false
    return try? URL(
        resolvingBookmarkData: data,
        options: [.withoutUI, .withoutMounting],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    )
}

private struct SavedDocCard: View {
    let item: SavedDocItem
    var isMergeSource: Bool = false
    var isSelectingMergeTarget: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            if
                let data = item.thumbnailData,
                let img = UIImage(data: data)
            {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.05))
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 160)
            }
            
            Text(item.displayTitle)
                .font(.footnote)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Text(item.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var backgroundColor: Color {
        if isMergeSource {
            return Color.blue.opacity(0.15)
        }
        if isSelectingMergeTarget {
            return Color.clear
        }
        return Color(UIColor.secondarySystemBackground)
    }
}
