import SwiftUI

struct ClipboardScreen: PaletteScreen {
    let coordinator: ClipboardCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [ClipboardResult] { coordinator.results(for: vm.query) }
    var primaryActionTitle: String { vm.pasteTarget?.pasteTitle ?? "Copy" }

    private func result(at selection: Int) -> ClipboardResult? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func activate(at selection: Int) {
        coordinator.activateSelection()
    }

    func secondary(at selection: Int) -> Bool {
        guard let result = result(at: selection) else { return false }
        coordinator.activate(result, copyOnly: true)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .newItem, coordinator.snippetsEnabled { coordinator.editSnippet(nil); return true }
        guard let result = result(at: selection) else { return false }
        switch shortcut {
        case .copyFile, .copyText: coordinator.activate(result, copyOnly: true)
        case .delete: coordinator.delete(result)
        case .quickLook:
            guard case .item(let item) = result, item.type == .image else { return false }
            coordinator.expandedImage = item
        default: return false
        }
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let result = result(at: selection) else { return nil }
        var items = [
            PopoverMenuItem(title: primaryActionTitle, systemImage: "doc.on.clipboard", shortcut: "↩") {
                coordinator.activate(result)
            },
            PopoverMenuItem(title: "Copy", systemImage: "doc.on.doc", shortcut: "⌘C") {
                coordinator.activate(result, copyOnly: true)
            }
        ]
        switch result {
        case .item(let item):
            if item.type == .text, coordinator.snippetsEnabled {
                items.append(PopoverMenuItem(title: "Save as Snippet…", systemImage: "text.badge.plus") {
                    coordinator.editSnippet(result)
                })
            } else if item.type == .image {
                items.append(PopoverMenuItem(title: "Enlarge Image", systemImage: "arrow.up.left.and.arrow.down.right", shortcut: "⌘Y") {
                    coordinator.expandedImage = item
                })
                items.append(PopoverMenuItem(title: "Copy Text from Image", systemImage: "text.viewfinder") {
                    coordinator.copyImageText(item)
                })
            }
        case .snippet:
            items.append(PopoverMenuItem(title: "Edit Snippet…", systemImage: "pencil") {
                coordinator.editSnippet(result)
            })
        }
        items.append(PopoverMenuItem(title: "Delete", systemImage: "trash", startsSection: true, shortcut: "⌃X", isDestructive: true) {
            coordinator.delete(result)
        })
        return PopoverMenuContent(items: items)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(ClipboardPaletteView(
            coordinator: coordinator, vm: vm, rows: rows, selected: result(at: selection),
            scroll: scroll, openActions: openActions, primaryTitle: primaryActionTitle))
    }
}

private struct ClipboardPaletteView: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let coordinator: ClipboardCoordinator
    let vm: PaletteState
    let rows: [ClipboardResult]
    let selected: ClipboardResult?
    let scroll: ScrollIntent
    let openActions: () -> Void
    let primaryTitle: String

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, result in
                            row(result, selected: result.id == selected?.id)
                                .contentShape(Rectangle())
                                .onRowClick(
                                    select: { vm.selection = index },
                                    activate: { coordinator.activate(result) })
                                .onRightClick { vm.selection = index; openActions() }
                                .id(result.id)
                        }
                    }
                    .padding(metrics.scaled(4))
                    .scrollOriginAnchor()
                }
                .hideNativeScrollers()
                .thinScrollbar()
                .scrollFollowsSelection(scroll, row: selected?.id, atOrigin: selected?.id == rows.first?.id, proxy: proxy)
            }
            .overlay {
                if rows.isEmpty {
                    Text(coordinator.store.error ?? (coordinator.searchSession.isSearching ? "Searching…" : "No items"))
                        .font(.system(size: metrics.scaled(12)))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: metrics.scaled(Theme.Size.clipboardListWidth))
            Rectangle().fill(Theme.Colors.separator).frame(width: 1)
            ClipboardPalettePreview(result: selected, coordinator: coordinator, primaryTitle: primaryTitle, openActions: openActions, deferLoading: scroll.kind == .follow)
                .id(selected?.id)
        }
        .overlay {
            if let item = coordinator.expandedImage {
                ClipboardExpandedImage(item: item, coordinator: coordinator)
            }
        }
        .onChange(of: selected?.id) { coordinator.expandedImage = nil }
        .onChange(of: coordinator.store.items) { coordinator.refreshSearch() }
        .onChange(of: coordinator.snippets.snippets) { coordinator.snippetsChanged() }
        .onChange(of: coordinator.store.isLoaded) { coordinator.refreshSearch() }
        .onAppear { coordinator.refreshSearch() }
    }

    @ViewBuilder
    private func row(_ result: ClipboardResult, selected: Bool) -> some View {
        switch result {
        case .item(let item):
            ClipboardItemRow(item: item, store: coordinator.store, isSelected: selected)
        case .snippet(let snippet):
            HStack(spacing: metrics.scaled(8)) {
                Text(":\(snippet.trigger)").foregroundStyle(.secondary)
                Text(snippet.displayTitle).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: metrics.scaled(12)))
            .padding(.horizontal, metrics.scaled(8))
            .frame(height: metrics.scaled(settings.paletteDensity.clipboardRowHeight))
            .background(selected ? Theme.Colors.selection : .clear, in: RoundedRectangle(cornerRadius: metrics.scaled(5)))
        }
    }
}

private struct ClipboardPalettePreview: View {
    @Environment(\.metrics) private var metrics
    let result: ClipboardResult?
    let coordinator: ClipboardCoordinator
    let primaryTitle: String
    let openActions: () -> Void
    let deferLoading: Bool
    @State private var text = ""
    @State private var image: NSImage?
    @State private var limit = 2_000
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let result {
                HStack {
                    Text(title(result)).foregroundStyle(.secondary)
                    Spacer()
                    if coordinator.extractingText { ProgressView().controlSize(.mini) }
                    Button(action: openActions) { Image(systemName: "ellipsis") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Actions")
                }
                .font(.system(size: metrics.scaled(11)))
                .padding(metrics.scaled(12))
                if case .item(let item) = result, item.type == .image {
                    if let image {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .padding(metrics.scaled(12))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture { coordinator.expandedImage = item }
                    } else {
                        Text(error ?? "Loading image…").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: metrics.scaled(12)) {
                            Text(error ?? (text.isEmpty ? String(result.text.prefix(1_000)) : text))
                                .font(.system(size: metrics.scaled(12)))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if hasMore && limit < 8_000 {
                                Button("Show more") { limit += 2_000 }
                                    .buttonStyle(.plain)
                                    .disabled(loading)
                            } else if hasMore {
                                Text("Preview limited to 8,000 characters").foregroundStyle(.secondary)
                            }
                            if case .item(let item) = result, item.isTruncated {
                                Text("Saved content is truncated").foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: metrics.scaled(11)))
                        .padding(.horizontal, metrics.scaled(12))
                        .padding(.bottom, metrics.scaled(12))
                    }
                    .hideNativeScrollers()
                    .thinScrollbar()
                }
                HStack {
                    Spacer()
                    Button(primaryTitle) { coordinator.activate(result) }
                        .buttonStyle(.plain)
                    Image(systemName: "return").foregroundStyle(.tertiary)
                }
                .font(.system(size: metrics.scaled(11)))
                .padding(metrics.scaled(12))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: result?.id) {
            limit = 2_000
            text = String((result?.text ?? "").prefix(1_000))
            image = nil
            error = nil
            hasMore = false
            await load()
        }
        .task(id: limit) { if limit > 2_000 { await load() } }
    }

    private func title(_ result: ClipboardResult) -> String {
        switch result {
        case .snippet(let snippet): ":\(snippet.trigger)"
        case .item(let item):
            if let bytes = item.originalSizeBytes {
                "\(item.type == .image ? "Image" : "Text") · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
            } else if item.type == .text { "Text · \((item.textContent ?? "").count) characters" }
            else { "Image" }
        }
    }

    private func load() async {
        guard let result else { return }
        loading = true
        defer { loading = false }
        switch result {
        case .snippet(let snippet):
            text = String(snippet.content.prefix(limit))
            hasMore = snippet.content.count > limit
        case .item(let item):
            let storage = coordinator.store.storage
            if item.type == .image {
                let loaded = await storage.imageCache.preview(for: item)
                guard !Task.isCancelled else { return }
                image = loaded
                if loaded == nil { error = "Image unavailable" }
            } else {
                if deferLoading && (item.isFileBacked || (item.textContent?.count ?? 0) > 1_000) {
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                }
                let source = storage.textChunkSource(for: item)
                let count = limit
                let chunk = await Task.detached(priority: .utility) { ClipboardStorage.readTextChunk(from: source, charCount: count) }.value
                guard !Task.isCancelled else { return }
                if let chunk { text = chunk.text; hasMore = !chunk.reachedEOF }
                else { error = "Saved text unavailable" }
            }
        }
    }
}

private struct ClipboardExpandedImage: View {
    let item: ClipboardItem
    let coordinator: ClipboardCoordinator
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            HStack {
                Spacer()
                Button("Close") { coordinator.expandedImage = nil }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .task(id: item.id) { image = await coordinator.store.storage.imageCache.preview(for: item) }
    }
}
