import SwiftUI
import AppKit

// MARK: - WindowCard

struct WindowCard: View {

    let item: WindowItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    private let cardWidth: CGFloat = 250
    private let cardHeight: CGFloat = 188

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main card button
            Button(action: onSelect) {
                VStack(spacing: 8) {
                    thumbnailView
                    labelView
                }
                .padding(10)
                .frame(width: cardWidth)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(selectionBorder)
            }
            .buttonStyle(.plain)

            // Close button — inside ZStack so hover doesn't escape card
            if isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .frame(width: cardWidth)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    // MARK: - Subviews

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .frame(width: cardWidth - 20, height: cardHeight - 58)

            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: cardWidth - 20, height: cardHeight - 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var labelView: some View {
        HStack(spacing: 8) {
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.appName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.white.opacity(0.2))
        } else {
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
    }
}
