import SwiftUI
import AppKit

// MARK: - SwitcherOverlay

struct SwitcherOverlay: View {

    @Bindable var viewModel: TabiViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    spaceBar
                        .padding(.top, 24)

                    if viewModel.allWindows.isEmpty {
                        // Still loading
                        Spacer()
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Spacer()
                    } else if viewModel.windows.isEmpty {
                        // Space selected but has no windows
                        Spacer()
                        Text("No windows on this desktop")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                    } else {
                        windowGrid
                    }
                }

                // Gear button — absolute bottom-left
                Button {
                    viewModel.onOpenSettings?()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size:26))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 64, height: 64)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: 60, y: geo.size.height - 100)
            }
        }
    }

    // MARK: - Space bar

    private var spaceBar: some View {
        HStack(spacing: 8) {
            SpaceTab(
                label: "All",
                shortcut: "`",
                isActive: false,
                isSelected: viewModel.selectedSpaceId == nil
            ) {
                viewModel.selectSpace(nil)
            }

            let desktops = viewModel.spaces.filter { !$0.isFullscreen }
            ForEach(Array(desktops.enumerated()), id: \.element.id) { i, space in
                SpaceTab(
                    label: "Desktop \(i + 1)",
                    shortcut: "\(i + 1)",
                    isActive: space.isActive,
                    isSelected: viewModel.selectedSpaceId == space.id
                ) {
                    viewModel.selectSpace(space)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
    }

    // MARK: - Window grid

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
                .padding(.horizontal, 40)
                .padding(.vertical, 24)
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

// MARK: - SpaceTab

private struct SpaceTab: View {

    let label: String
    let shortcut: String
    let isActive: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                Text(shortcut)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
