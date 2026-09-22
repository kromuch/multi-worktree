import SwiftUI

enum MWT {
    static let width: CGFloat = 360
    static let hPadding: CGFloat = 14
    static let topPadding: CGFloat = 14
    static let bottomPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 18
    static let rowRadius: CGFloat = 9
    static let cardRadius: CGFloat = 10
}

struct PopoverRoot<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: MWT.width, alignment: .leading)
            .padding(.horizontal, MWT.hPadding)
            .padding(.top, MWT.topPadding)
            .padding(.bottom, MWT.bottomPadding)
    }
}

struct IconBadge: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct ScreenHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var tint: Color
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    init(symbol: String, title: String, subtitle: String? = nil, tint: Color = .accentColor,
         onBack: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Back")
            }
            IconBadge(symbol: symbol, tint: tint, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            Spacer()
            trailing
        }
    }
}

struct CardRow<Content: View>: View {
    var interactive: Bool = true
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: MWT.rowRadius, style: .continuous))
            .onHover { hovering = interactive && $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var fill: Color {
        hovering ? Color.primary.opacity(0.07) : Color.primary.opacity(0.035)
    }
}

struct GroupedCard<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: MWT.cardRadius, style: .continuous))
    }
}

struct InlineBanner: View {
    let text: String
    var symbol: String = "exclamationmark.triangle.fill"
    var tint: Color = .red
    var selectable: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol).font(.caption).foregroundStyle(tint)
            label
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var label: some View {
        if selectable {
            Text(text).textSelection(.enabled)
        } else {
            Text(text)
        }
    }
}

struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
    }
}

struct HintText: View {
    let text: String
    var symbol: String?

    init(_ text: String, symbol: String? = nil) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.caption2).foregroundStyle(.tertiary)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FooterBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Divider().padding(.top, 2)
        HStack(spacing: 8) { content }
    }
}
