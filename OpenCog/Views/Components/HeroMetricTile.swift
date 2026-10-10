import SwiftUI

/// An oversized metric for the numbers you glance at most while riding.
/// When `tinted`, the whole card takes on the tint (used for the heart-rate zone colour).
struct HeroMetricTile<Icon: View, Footer: View>: View {
    var title: String
    var value: String
    var unit: String
    var tint: Color
    var badge: String?
    var tinted: Bool
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var footer: () -> Footer

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var valueSize: CGFloat { horizontalSizeClass == .regular ? 112 : 64 }

    var body: some View {
        VStack(alignment: .leading, spacing: horizontalSizeClass == .regular ? 10 : 6) {
            HStack(spacing: 6) {
                icon()
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let badge, horizontalSizeClass == .regular {
                    Text(badge)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tinted ? .white : tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(tinted ? tint : tint.opacity(0.12), in: Capsule())
                        .lineLimit(1)
                }
            }
            .font(horizontalSizeClass == .regular ? .title3.weight(.semibold) : .subheadline.weight(.semibold))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: valueSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tinted ? tint : .primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(unit)
                    .font(horizontalSizeClass == .regular ? .title.weight(.semibold) : .headline)
                    .foregroundStyle(.secondary)
            }

            if let badge, horizontalSizeClass != .regular {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            footer()
        }
        .padding(horizontalSizeClass == .regular ? 22 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(tint.opacity(tinted ? 0.16 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(tint.opacity(tinted ? 0.45 : 0), lineWidth: 2)
        }
        .animation(.snappy, value: value)
        .animation(.easeInOut(duration: 0.6), value: tint)
        .accessibilityElement(children: .combine)
    }
}
