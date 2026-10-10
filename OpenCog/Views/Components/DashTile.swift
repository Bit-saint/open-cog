import SwiftUI

/// A metric tile that fills whatever frame the dashboard gives it, sizing its text from the
/// available space so the ride screen never needs to scroll.
struct DashTile<Icon: View, Footer: View>: View {
    var title: String
    var value: String
    var unit: String
    var tint: Color
    var detail: String?
    /// Hero tiles (heart rate, speed) get much larger numbers.
    var hero = false
    /// Tint the whole card (used for the heart-rate zone colour).
    var tinted = false
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let valueSize = hero ? min(h * 0.46, w * 0.30) : min(h * 0.40, w * 0.25)
            let labelSize = hero ? min(max(h * 0.09, 12), 20) : min(max(h * 0.13, 10), 15)
            let showBadge = hero && w > 320

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    icon().foregroundStyle(tint)
                    Text(title).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 2)
                    if showBadge, let detail {
                        Text(detail)
                            .foregroundStyle(tinted ? .white : tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(tinted ? tint : tint.opacity(0.12), in: Capsule())
                            .lineLimit(1)
                    }
                }
                .font(.system(size: labelSize, weight: .semibold))

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: max(valueSize, 14), weight: hero ? .heavy : .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tinted ? tint : .primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text(unit)
                        .font(.system(size: max(valueSize * 0.26, 10), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if !showBadge, let detail {
                    Text(detail)
                        .font(.system(size: min(max(h * 0.1, 9), 14), weight: .medium))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                footer()
            }
            .padding(hero ? min(16, h * 0.08) : min(10, h * 0.08))
            .frame(width: w, height: h, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: hero ? 22 : 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                RoundedRectangle(cornerRadius: hero ? 22 : 16, style: .continuous)
                    .fill(tint.opacity(tinted ? 0.16 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: hero ? 22 : 16, style: .continuous)
                    .strokeBorder(tint.opacity(tinted ? 0.45 : 0), lineWidth: 2)
            }
        }
        .animation(.snappy, value: value)
        .animation(.easeInOut(duration: 0.6), value: tint)
        .accessibilityElement(children: .combine)
    }
}

extension DashTile where Icon == Image, Footer == EmptyView {
    init(title: String, value: String, unit: String, systemImage: String, tint: Color, detail: String? = nil) {
        self.init(title: title, value: value, unit: unit, tint: tint, detail: detail) {
            Image(systemName: systemImage)
        } footer: {
            EmptyView()
        }
    }
}
