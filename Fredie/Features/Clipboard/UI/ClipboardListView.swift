import SwiftUI
import AppKit

struct ClipboardListView: View {
    let items: [ClipboardItem]
    @Binding var selectedIndex: Int
    @Binding var scrollTrigger: Bool
    let store: ClipboardStore
    let onSelect: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemRow(
                            item: item,
                            store: store,
                            isSelected: index == selectedIndex
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture(count: 1)
                                .onEnded { _ in
                                    selectedIndex = index
                                }
                        )
                        .highPriorityGesture(
                            TapGesture(count: 2)
                                .onEnded { _ in
                                    selectedIndex = index
                                    onSelect(item)
                                    onDismiss()
                                }
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .onChange(of: selectedIndex) { _, newValue in
                if scrollTrigger {
                    if let item = items[safe: newValue] {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(item.id)
                        }
                    }
                    scrollTrigger = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
                if let firstId = items.first?.id {
                    proxy.scrollTo(firstId, anchor: .top)
                }
            }
        }
    }
}
