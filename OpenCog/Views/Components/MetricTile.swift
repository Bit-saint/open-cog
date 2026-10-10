import SwiftUI

/// A single live metric: label, big rounded number, unit, and an optional zone/detail line.
struct MetricTile<Icon: View>: View {
    var title: String
    var value: String
    var unit: String
    var tint: Color = .accentColor
    var detail: String?
    var prominent = false
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                icon()
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: prominent ? 56 : 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(prominent ? .title3.weight(.semibold) : .headline)
                    .foregroundStyle(.secondary)
            }

            Text(detail ?? " ")
                .font(.caption.weight(.medium))
                .foregroundStyle(detail == nil ? Color.clear : tint)
                .lineLimit(1)
        }
        .card(padding: prominent ? 18 : 14)
        .overlay(alignment: .leading) {
            if prominent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 4)
                    .padding(.vertical, 18)
            }
        }
        .accessibilityElement(children: .combine)
        .animation(.snappy, value: value)
    }
}

extension MetricTile where Icon == Image {
    init(title: String, value: String, unit: String, systemImage: String, tint: Color = .accentColor,
         detail: String? = nil, prominent: Bool = false) {
        self.init(title: title, value: value, unit: unit, tint: tint, detail: detail, prominent: prominent) {
            Image(systemName: systemImage)
        }
    }
}
