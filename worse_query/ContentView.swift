// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Files Lab contributors

import SwiftUI
import UIKit
import QuickLook
import UniformTypeIdentifiers

private enum BrowserDestination: Hashable {
    case category(ContainerCategory)
    case folder(BrowserItem, String?)
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = BrowserModel()
    @State private var selectedTab = 0
    @State private var browsePath: [BrowserDestination] = []
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $browsePath) {
                BrowseScreen(model: model)
                    .navigationDestination(for: BrowserDestination.self) { destination in
                        DestinationScreen(destination: destination, model: model)
                    }
            }
            .tabItem { Label("Browse", systemImage: "folder") }.tag(0)
            NavigationStack {
                FavoritesScreen(model: model)
                    .navigationDestination(for: BrowserDestination.self) { destination in
                        DestinationScreen(destination: destination, model: model)
                    }
            }
            .tabItem { Label("Favorites", systemImage: "star") }.tag(1)
            NavigationStack { ActivityScreen(log: model.activity) }
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }.tag(2)
            NavigationStack { AboutScreen() }
                .tabItem { Label("About", systemImage: "info.circle") }.tag(3)
        }
        .tint(.blue)
        .statusBarHidden(ScreenshotData.enabled)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.activity.Flush() }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--show-activity") { selectedTab = 2 }
            if ProcessInfo.processInfo.arguments.contains("--show-about") { selectedTab = 3 }
            #if DEBUG
            if ScreenshotData.enabled && (ProcessInfo.processInfo.arguments.contains("--preview-delete-progress") ||
                                          ProcessInfo.processInfo.arguments.contains("--preview-move-progress") ||
                                          ProcessInfo.processInfo.arguments.contains("--preview-copy-progress")) {
                let folder = BrowserItem(path: "/Examples/Notes", name: "Notes", isDirectory: true, size: 0)
                browsePath = [.folder(folder, nil)]
                let moving = ProcessInfo.processInfo.arguments.contains("--preview-move-progress")
                let copying = ProcessInfo.processInfo.arguments.contains("--preview-copy-progress")
                let title = moving ? "Moving folder" : (copying ? "Copying file" : "Deleting folder")
                let symbol = moving ? "folder.fill" : (copying ? "doc.on.doc" : "trash")
                let id = model.operationStatus.Begin(title, symbol: symbol)
                if copying {
                    model.operationStatus.Update(id, .init(stage: "Copying", completed: 2_097_152,
                                                         total: 5_242_880, unit: .bytes))
                } else {
                    model.operationStatus.Update(id, .init(stage: moving ? "Moving" : "Deleting",
                                                         completed: 3, total: 7, unit: .items))
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--check-pinned-search") {
                UserDefaults.standard.set(FolderLayout.list.rawValue, forKey: "FolderLayout")
                browsePath = [.category(ContainerCategory.all[1])]
            }
            if ProcessInfo.processInfo.arguments.contains("--check-icons") {
                UserDefaults.standard.set(FolderLayout.icons.rawValue, forKey: "FolderLayout")
                browsePath = [.category(ContainerCategory.all[1])]
            }
            if ProcessInfo.processInfo.arguments.contains("--show-documents"),
               let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                browsePath = [.folder(BrowserItem(path: documents.path, name: "Documents", isDirectory: true, size: 0), nil)]
            }
            if ProcessInfo.processInfo.arguments.contains("--verify-file-operations") {
                let arguments = ProcessInfo.processInfo.arguments
                let index = arguments.firstIndex(of: "--operation-test-directory")
                let parent = index.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
                await model.VerifyFileOperations(parent: parent)
            }
            if ProcessInfo.processInfo.arguments.contains("--verify-view-options") {
                let valid = FolderOrdering.Verify()
                model.Log(valid ? "View options verified" : "View options failed",
                          detail: "Name, kind, date, size, order, hidden files, folders first, search", kind: valid ? .success : .error)
            }
            #endif
            if ProcessInfo.processInfo.arguments.contains("--verify-browser") { await model.Verify() }
        }
    }
}

private struct BrowseScreen: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        List {
            Section("On This iPhone") {
                ForEach(ContainerCategory.all) { category in
                    NavigationLink(value: BrowserDestination.category(category)) {
                        Label {
                            HStack {
                                Text(category.name)
                                Spacer()
                                if let count = model.containers[category.path]?.count {
                                    Text("\(count)").foregroundStyle(.secondary)
                                }
                            }
                        } icon: { Image(systemName: category.symbol).foregroundStyle(.blue) }
                    }
                }
            }
            Section("Locations") {
                NavigationLink(value: BrowserDestination.folder(
                    .init(path: "/", name: "File System", isDirectory: true, size: 0), nil)) {
                    Label("File System", systemImage: "internaldrive")
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    NavigationLink(value: BrowserDestination.folder(
                        .init(path: documents.path, name: "Documents", isDirectory: true, size: 0), nil)) {
                        Label("Documents", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Browse")
    }
}

private struct DestinationScreen: View {
    let destination: BrowserDestination
    @ObservedObject var model: BrowserModel
    var body: some View {
        switch destination {
        case .category(let category): ContainerScreen(category: category, model: model)
        case .folder(let item, let root): FolderScreen(item: item, root: root, model: model)
        }
    }
}

private struct ContainerScreen: View {
    let category: ContainerCategory
    @ObservedObject var model: BrowserModel
    @State private var search = ""
    @AppStorage("FolderLayout") private var layout: FolderLayout = .list
    @AppStorage("FolderSort") private var sort: FolderSort = .name
    @AppStorage("SortAscending") private var ascending = true
    @AppStorage("FoldersFirst") private var foldersFirst = true
    @AppStorage("ShowHidden") private var showHidden = true
    private var items: [BrowserItem] {
        FolderOrdering.Arrange(model.containers[category.path] ?? [], search: search,
            sort: sort, ascending: ascending, foldersFirst: foldersFirst, showHidden: showHidden)
    }
    var body: some View {
        ScrollViewReader { proxy in
            FileCollection(layout: layout) {
                ForEach(items) { item in
                    NavigationLink(value: BrowserDestination.folder(item, item.path)) {
                        let count = item.itemCount ?? Int(item.size)
                        let detail = "\(count) \(count == 1 ? "item" : "items")"
                        if layout == .icons { FileTile(item: item, detail: detail) }
                        else { FileRow(item: item, detail: detail) }
                    }
                    .contextMenu { FavoriteButton(item: item, model: model) }
                }
            }
            .overlay {
                if items.isEmpty {
                    if model.loading.contains(category.path) { ProgressView("Finding folders…") }
                    else if let error = model.errors[category.path] {
                        FolderError(message: error) { Task { await model.Discover(category, force: true) } }
                    } else { ContentUnavailableView(search.isEmpty ? "No Folders Found" : "No Results", systemImage: "folder") }
                }
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { PinnedSearchBar(text: $search, prompt: "Search") }
            .safeAreaInset(edge: .bottom, spacing: 0) { FolderCount(count: items.count) }
            .refreshable { await model.Discover(category, force: true) }
            .toolbar {
                Menu {
                    FolderViewOptions()
                    Section {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await model.Discover(category, force: true) }
                        }.disabled(model.loading.contains(category.path))
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("View and Sort Options")
            }
            .onChange(of: sort) { _, value in
                if value == .date && (model.containers[category.path]?.contains { $0.modifiedDate == nil } ?? false) {
                    Task { await model.Discover(category, force: true) }
                }
            }
            .task {
                let missingDates = sort == .date && (model.containers[category.path]?.contains { $0.modifiedDate == nil } ?? false)
                await model.Discover(category, force: missingDates)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--check-pinned-search") {
                    try? await Task.sleep(for: .milliseconds(600))
                    if let last = items.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                #endif
            }
        }
    }
}

private enum TransferMode { case copy, move }

private final class PendingTransfer {
    let source: URL
    let mode: TransferMode
    private let scoped: Bool
    init(source: URL, mode: TransferMode = .copy) {
        self.source = source
        self.mode = mode
        scoped = source.startAccessingSecurityScopedResource()
    }
    deinit { if scoped { source.stopAccessingSecurityScopedResource() } }
}

private struct FolderScreen: View {
    let item: BrowserItem
    let root: String?
    @ObservedObject var model: BrowserModel
    @State private var items: [BrowserItem] = []
    @State private var loading = true
    @State private var message: String?
    @State private var search = ""
    @State private var preview: BrowserItem?
    @State private var busy = false
    @State private var newFolder = false
    @State private var renameItem: BrowserItem?
    @State private var deleteItem: BrowserItem?
    @State private var nameInput = ""
    @State private var importing = false
    @State private var pendingCopy: PendingTransfer?
    @State private var operationError: String?
    @State private var feedbackPath: String?
    @AppStorage("FolderLayout") private var layout: FolderLayout = .list
    @AppStorage("FolderSort") private var sort: FolderSort = .name
    @AppStorage("SortAscending") private var ascending = true
    @AppStorage("FoldersFirst") private var foldersFirst = true
    @AppStorage("ShowHidden") private var showHidden = true
    private var filtered: [BrowserItem] {
        FolderOrdering.Arrange(items, search: search, sort: sort, ascending: ascending,
                               foldersFirst: foldersFirst, showHidden: showHidden)
    }
    var body: some View {
        FileCollection(layout: layout) {
            ForEach(filtered) { entry in
                EntryView(entry)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .disabled(busy)
        .overlay {
            if loading && items.isEmpty { ProgressView("Opening folder…") }
            else if let message, items.isEmpty { FolderError(message: message) { Task { await Load(refresh: true) } } }
            else if filtered.isEmpty { ContentUnavailableView(search.isEmpty ? "Empty Folder" : "No Results", systemImage: "folder") }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                PinnedSearchBar(text: $search, prompt: "Search")
                OperationBanner(status: model.operationStatus)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { FolderCount(count: filtered.count) }
        .toolbar {
            Menu {
                Section {
                    Button("New Folder", systemImage: "folder.badge.plus") { nameInput = "New Folder"; newFolder = true }
                    Button("Import File…", systemImage: "square.and.arrow.down") { importing = true }
                    if let copied = model.copiedItem {
                        Button("Paste “\(copied.name)”", systemImage: "doc.on.clipboard") { BeginCopy(copied.url) }
                        Button("Cancel Copy", systemImage: "xmark") { model.copiedItem = nil }
                    }
                    if let moving = model.movingItem {
                        Button("Move “\(moving.name)” Here", systemImage: "folder.fill") {
                            BeginCopy(moving.url, mode: .move)
                        }
                        Button("Cancel Move", systemImage: "xmark") { model.movingItem = nil }
                    }
                }
                FolderViewOptions()
                Section {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await Load(refresh: true) } }
                    FavoriteButton(item: item, model: model)
                    Button("Copy Path", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.directoryPath }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Folder actions, view and sort options")
            .disabled(busy)
        }
        .refreshable { if !busy { await Load(refresh: true) } }
        .task {
            await Load()
        }
        .sheet(item: $preview) { entry in PreviewScreen(item: entry) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let first = urls.first { BeginCopy(first) }
            case .failure(let error): operationError = error.localizedDescription
            }
        }
        .alert("New Folder", isPresented: $newFolder) {
            TextField("Name", text: $nameInput)
            Button("Cancel", role: .cancel) { }
            Button("Create") { let name = nameInput; Task { await Run(.newFolder(parent: item.directoryPath, name: name)) } }
        }
        .alert("Rename", isPresented: Binding(get: { renameItem != nil }, set: { if !$0 { renameItem = nil } }), presenting: renameItem) { entry in
            TextField("Name", text: $nameInput)
            Button("Cancel", role: .cancel) { renameItem = nil }
            Button("Save") {
                let name = nameInput; renameItem = nil
                Task { await Run(.rename(path: entry.path, name: name)) }
            }
        }
        .confirmationDialog("Delete “\(deleteItem?.name ?? "item")”?", isPresented: Binding(
            get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } }), titleVisibility: .visible, presenting: deleteItem) { entry in
            Button("Delete", role: .destructive) {
                deleteItem = nil
                Task { await Run(.delete(path: entry.path)) }
            }
        } message: { _ in Text("This permanently deletes the selected item and any contents.") }
        .confirmationDialog("An item named “\(pendingCopy?.source.lastPathComponent ?? "item")” already exists.", isPresented: Binding(
            get: { pendingCopy != nil }, set: { if !$0 { pendingCopy = nil } }), titleVisibility: .visible, presenting: pendingCopy) { request in
            Button("Keep Both") { pendingCopy = nil; Task { await Copy(request, policy: .keepBoth) } }
            Button("Replace File", role: .destructive) {
                pendingCopy = nil
                Task { await Copy(request, policy: .replace) }
            }
            Button("Cancel", role: .cancel) { pendingCopy = nil }
        } message: { _ in Text("The destination is prepared first, then the new file replaces the old one. For a move, the source is removed only after the destination is ready. Folders cannot be replaced.") }
        .alert("Couldn’t Complete Action", isPresented: Binding(
            get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: { Text(operationError ?? "Unknown error") }
        .onDisappear { pendingCopy = nil }
    }

    @ViewBuilder private func EntryView(_ entry: BrowserItem) -> some View {
        if entry.isDirectory {
            if let category = ContainerCategory.all.first(where: { $0.path == entry.directoryPath }) {
                NavigationLink(value: BrowserDestination.category(category)) { ItemLabel(entry) }
            } else {
                NavigationLink(value: BrowserDestination.folder(entry, model.Root(for: entry.directoryPath) ?? root)) { ItemLabel(entry) }
                    .contextMenu { ItemActions(entry) }
            }
        } else {
            Button { preview = entry } label: { ItemLabel(entry) }
                .buttonStyle(.plain)
                .contextMenu { ItemActions(entry) }
        }
    }

    @ViewBuilder private func ItemLabel(_ entry: BrowserItem) -> some View {
        VStack(spacing: 4) {
            Group {
                if layout == .icons { FileTile(item: entry) } else { FileRow(item: entry) }
            }
            .padding(.horizontal, 4)
            .background(feedbackPath == entry.path ? Color.blue.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }
    }
    @ViewBuilder private func ItemActions(_ entry: BrowserItem) -> some View {
        Button("Copy", systemImage: "doc.on.doc") { model.Copy(entry) }
        Button("Move", systemImage: "folder.fill") { model.Move(entry) }
        Button("Rename", systemImage: "pencil") { nameInput = entry.name; renameItem = entry }
        ShareLink(item: entry.url) { Label("Share", systemImage: "square.and.arrow.up") }
        if entry.isDirectory { FavoriteButton(item: entry, model: model) }
        Button("Copy Path", systemImage: "link") { UIPasteboard.general.string = entry.path }
        Button("Delete", systemImage: "trash", role: .destructive) { deleteItem = entry }
    }
    private func Load(refresh: Bool = false, animated: Bool = false) async {
        loading = true
        defer { loading = false }
        do {
            let refreshed = try await model.Directory(item.directoryPath, root: root, refresh: refresh)
            if animated { withAnimation(.smooth(duration: 0.42)) { items = refreshed } }
            else { items = refreshed }
            message = nil
        }
        catch { message = error.localizedDescription }
    }
    private func Run(_ operation: FileOperation) async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do {
            let result = try await model.Mutate(operation)
            await Load(refresh: true, animated: true)
            if case .delete = operation { return }
            Flash(result.path)
        } catch {
            await Load(refresh: true, animated: true)
            operationError = error.localizedDescription
        }
    }
    private func BeginCopy(_ source: URL, mode: TransferMode = .copy) {
        guard !busy else { return }
        let request = PendingTransfer(source: source, mode: mode)
        Task { await Copy(request, policy: .fail) }
    }
    private func Copy(_ request: PendingTransfer, policy: CollisionPolicy) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let operation: FileOperation = request.mode == .move
                ? .move(source: request.source.path, directory: item.directoryPath, policy: policy)
                : .copy(source: request.source.path, directory: item.directoryPath, policy: policy)
            let result = try await model.Mutate(operation)
            if request.mode == .move { model.movingItem = nil }
            await Load(refresh: true, animated: true)
            Flash(result.path)
        } catch FileActionError.exists {
            pendingCopy = request
        } catch {
            if request.mode == .move { await Load(refresh: true, animated: true) }
            operationError = error.localizedDescription
        }
    }

    private func Flash(_ path: String) {
        withAnimation(.easeIn(duration: 0.18)) { feedbackPath = path }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            if feedbackPath == path {
                withAnimation(.easeOut(duration: 0.42)) { feedbackPath = nil }
            }
        }
    }

}

private struct OperationBanner: View {
    @ObservedObject var status: OperationStatus
    var body: some View {
        Group {
            if let active = status.active {
                HStack(spacing: 12) {
                    Image(systemName: active.symbol)
                        .foregroundStyle(active.symbol == "trash" ? Color.red : Color.blue)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(active.update?.stage ?? active.title).font(.subheadline.weight(.semibold))
                        if let update = active.update {
                            if let fraction = update.fraction { ProgressView(value: fraction) }
                            else { ProgressView() }
                            Text(update.detail).font(.caption).foregroundStyle(.secondary)
                        } else { ProgressView() }
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16).padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let feedback = status.feedback {
                Label(feedback.title, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.green)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: status.active?.id)
        .animation(.smooth(duration: 0.3), value: status.feedback?.id)
    }
}

private struct FileCollection<Content: View>: View {
    let layout: FolderLayout
    @ViewBuilder let content: () -> Content
    var body: some View {
        Group {
            if layout == .list {
                List { content() }.listStyle(.plain)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 20)], spacing: 24) { content() }
                        .padding(.horizontal, 20).padding(.vertical, 20)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct FolderViewOptions: View {
    @AppStorage("FolderLayout") private var layout: FolderLayout = .list
    @AppStorage("FolderSort") private var sort: FolderSort = .name
    @AppStorage("SortAscending") private var ascending = true
    @AppStorage("FoldersFirst") private var foldersFirst = true
    @AppStorage("ShowHidden") private var showHidden = true
    var body: some View {
        Section {
            Picker("View", selection: $layout) {
                Label("Icons", systemImage: "square.grid.2x2").tag(FolderLayout.icons)
                Label("List", systemImage: "list.bullet").tag(FolderLayout.list)
            }.pickerStyle(.inline)
        }
        Section {
            Picker("Sort By", selection: $sort) {
                ForEach(FolderSort.allCases, id: \.self) { key in Text(key.label).tag(key) }
            }.pickerStyle(.inline)
        }
        Section {
            Picker("Order", selection: $ascending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            Toggle("Folders First", isOn: $foldersFirst)
            Toggle("Show Hidden Files", isOn: $showHidden)
        }
    }
}

private struct FileTile: View {
    let item: BrowserItem
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(item.isDirectory ? Color.blue : Color.secondary)
                .frame(height: 58)
            Text(item.name).font(.subheadline).foregroundStyle(Color.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            if let detail { Text(detail).font(.caption2).foregroundStyle(Color.secondary) }
            else if !item.isDirectory {
                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    .font(.caption2).foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .top)
        .contentShape(Rectangle())
    }
}

private struct FolderCount: View {
    let count: Int
    var body: some View {
        Text("\(count) \(count == 1 ? "item" : "items")")
            .font(.caption).foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.32), value: count)
            .frame(maxWidth: .infinity).padding(.vertical, 6).background(.bar)
    }
}

private struct FolderError: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Folder Unavailable", systemImage: "folder.badge.questionmark")
        } description: { Text(message) }
        actions: { Button("Try Again", action: retry) }
    }
}

// This header is outside the List's scroll area, so it never scrolls away.
private struct PinnedSearchBar: View {
    @Binding var text: String
    let prompt: String
    var body: some View {
        NativeSearchBar(text: $text, prompt: prompt)
            .frame(height: 56)
            .padding(.horizontal, 8)
    }
}

private struct NativeSearchBar: UIViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = prompt
        bar.autocapitalizationType = .none
        bar.autocorrectionType = .no
        bar.returnKeyType = .search
        bar.delegate = context.coordinator
        bar.searchTextField.accessibilityIdentifier = "PinnedFolderSearch"
        return bar
    }
    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.text = $text
        if bar.text != text { bar.text = text }
        bar.placeholder = prompt
    }
    final class Coordinator: NSObject, UISearchBarDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text.wrappedValue = searchText
        }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
    }
}

private struct FileRow: View {
    let item: BrowserItem
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 27))
                .foregroundStyle(item.isDirectory ? Color.blue : Color.secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body).foregroundStyle(.primary).lineLimit(2)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                else if !item.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct FavoriteButton: View {
    let item: BrowserItem
    @ObservedObject var model: BrowserModel
    var body: some View {
        Button(model.favorites.contains(where: { $0.path == item.path }) ? "Remove Favorite" : "Add to Favorites",
            systemImage: "star") { model.ToggleFavorite(item) }
    }
}

private struct FavoritesScreen: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        List {
            ForEach(model.favorites) { item in
                NavigationLink(value: BrowserDestination.folder(item, model.Root(for: item.directoryPath))) { FileRow(item: item) }
            }
            .onDelete { indices in
                for index in indices.sorted(by: >) { model.ToggleFavorite(model.favorites[index]) }
            }
        }
        .overlay {
            if model.favorites.isEmpty {
                ContentUnavailableView("No Favorites", systemImage: "star",
                    description: Text("Touch and hold a folder to save it here."))
            }
        }
        .navigationTitle("Favorites")
    }
}

private extension EventKind {
    var symbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .info: .blue
        case .success: .green
        case .error: .red
        }
    }
    var label: String { rawValue.capitalized }
}

private struct ActivityScreen: View {
    @ObservedObject var log: ActivityLog
    @State private var search = ""
    @State private var errorsOnly = false
    @State private var selectedEvent: BrowserEvent?
    @State private var confirmingClear = false

    private var filtered: [BrowserEvent] {
        log.events.reversed().filter { event in
            (!errorsOnly || event.isError) && (search.isEmpty ||
                event.message.localizedCaseInsensitiveContains(search) ||
                (event.path?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    var body: some View {
        let entries = filtered
        List {
            Section {
                HStack(spacing: 16) {
                    ActivityMetric(value: log.events.count, label: "Events", symbol: "list.bullet", color: .blue)
                    Divider()
                    ActivityMetric(value: log.events.filter(\.isError).count, label: "Errors", symbol: "exclamationmark.circle", color: .red)
                }
                .padding(.vertical, 6)
                Picker("Show activity", selection: $errorsOnly) {
                    Text("All Activity").tag(false)
                    Text("Errors").tag(true)
                }
                .pickerStyle(.segmented)
            }
            if entries.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? (errorsOnly ? "No Errors" : "No Activity Yet") : "No Results",
                    systemImage: search.isEmpty ? (errorsOnly ? "checkmark.seal" : "clock") : "magnifyingglass",
                    description: Text(errorsOnly ? "Access problems will appear here." : "Folder browsing and discovery events appear here.")
                )
            } else {
                Section("Most Recent First") {
                    ForEach(entries) { event in
                        Button { selectedEvent = event } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: event.kind.symbol)
                                    .font(.title3)
                                    .foregroundStyle(event.kind.color)
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(event.title).font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer(minLength: 6)
                                        Text(event.date, style: .time).font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !event.detail.isEmpty {
                                        Text(event.detail).font(.subheadline)
                                            .foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    if let path = event.path {
                                        Text(path).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                                    .padding(.top, 7)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Copy Event", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = log.Export([event])
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            PinnedSearchBar(text: $search, prompt: "Search events or paths")
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            Menu {
                ShareLink(item: log.Export(Array(entries.reversed()))) {
                    Label("Export Displayed Events", systemImage: "square.and.arrow.up")
                }
                Button("Clear Activity", systemImage: "trash", role: .destructive) {
                    confirmingClear = true
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Activity actions")
        }
        .confirmationDialog("Clear all activity?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear Activity", role: .destructive) { log.Clear() }
        } message: { Text("This removes the saved activity history.") }
        .sheet(item: $selectedEvent) { event in EventDetailScreen(event: event, log: log) }
    }
}

private struct ActivityMetric: View {
    let value: Int
    let label: String
    let symbol: String
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(value, format: .number).font(.title2.weight(.semibold)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct EventDetailScreen: View {
    let event: BrowserEvent
    @ObservedObject var log: ActivityLog
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(event.title, systemImage: event.kind.symbol)
                        .foregroundStyle(event.kind.color).font(.headline)
                    if !event.detail.isEmpty { Text(event.detail).textSelection(.enabled) }
                }
                Section("Details") {
                    LabeledContent("Status", value: event.kind.label)
                    LabeledContent("Time", value: event.date.formatted(date: .abbreviated, time: .standard))
                    if let duration = event.duration {
                        LabeledContent("Duration", value: String(format: "%.2f seconds", duration))
                    }
                }
                if let path = event.path {
                    Section("Location") {
                        Text(path).font(.subheadline).textSelection(.enabled)
                        Button("Copy Path", systemImage: "doc.on.doc") { UIPasteboard.general.string = path }
                    }
                }
                Section {
                    ShareLink(item: log.Export([event])) { Label("Share Event", systemImage: "square.and.arrow.up") }
                    Button("Copy Event", systemImage: "doc.on.doc") { UIPasteboard.general.string = log.Export([event]) }
                }
            }
            .navigationTitle("Event Details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct PreviewScreen: View {
    let item: BrowserItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            QuickLookPreview(url: item.url)
                .navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) { }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
