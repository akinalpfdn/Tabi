import SwiftUI
import AppKit

// MARK: - SwitcherOverlay

struct SwitcherOverlay: View {

    @Bindable var viewModel: TabiViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            if viewModel.windows.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            } else {
                windowGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid

    private var windowGrid: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                let columns = gridColumns()
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.windows) { item in
                        WindowCard(
                            item: item,
                            isSelected: viewModel.windows[safe: viewModel.selectedIndex] == item,
                            onSelect: { viewModel.select(item) },
                            onClose: { viewModel.close(item) }
                        )
                        .id(item.id)
                    }
                }
                .padding(40)
            }
            .onChange(of: viewModel.selectedIndex) { _, index in
                if let item = viewModel.windows[safe: index] {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func gridColumns() -> [GridItem] {
        let count = min(viewModel.windows.count, 6)
        return Array(repeating: GridItem(.fixed(250), spacing: 16), count: max(count, 1))
    }
}

// MARK: - Safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
