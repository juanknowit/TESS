import SwiftUI

/// TESS's dark, blue-accented look (inspired by Vorssaint).
enum Theme {
    static let window = Color(hex: 0x0E0E16)
    static let sidebar = Color(hex: 0x12121B)
    static let card = Color(hex: 0x191923)
    static let tile = Color(hex: 0x21212D)
    static let field = Color(hex: 0x0F0F17)
    static let stroke = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.12)
    static let accent = Color(hex: 0x0A84FF)
    static let cyan = Color(hex: 0x46D7FF)
    static let text = Color.white.opacity(0.93)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.35)
    static let green = Color(hex: 0x32D74B)
    static let orange = Color(hex: 0xFF9F0A)
    static let red = Color(hex: 0xFF453A)

    static let claude = Color(hex: 0xD97757)
    static let openAI = Color(hex: 0x7C8CF8)
    static let ollama = Color(hex: 0xD8D8E0)

    static func providerColor(_ name: String) -> Color {
        switch name {
        case "Claude": return claude
        case "OpenAI": return openAI
        default: return ollama
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Building blocks

/// Rounded section container.
struct Card<Content: View>: View {
    var title: String?
    var trailingTitle: String?
    var footer: String?
    let content: Content

    init(_ title: String? = nil, trailing: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailingTitle = trailing
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    HStack {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        if let trailingTitle {
                            Text(trailingTitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                }
                content
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))

            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct IconBadge: View {
    let icon: String
    var tint: Color = Theme.accent
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(tint.opacity(0.14)))
    }
}

/// A setting: icon, title, explanation and a control on the right.
struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = Theme.accent
    let trailing: Trailing

    init(_ icon: String, _ title: String, subtitle: String? = nil, tint: Color = Theme.accent,
         @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(icon: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 56)
    }
}

/// Big selectable choice, like "Compact / Spacious / Custom".
struct OptionTile: View {
    let icon: String
    let title: String
    var subtitle: String?
    let selected: Bool
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(selected ? tint : Theme.text)
                    .frame(height: 26)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? tint : Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? tint.opacity(0.12) : Theme.tile))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? tint : Theme.stroke, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Small coloured label, e.g. "Granted" or "Local".
struct Pill: View {
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(_ title: String, _ subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
        .padding(.top, 4)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, _ subtitle: String) {
        self.init(title, subtitle) { EmptyView() }
    }
}

/// Horizontal progress bar with rounded ends.
struct MeterBar: View {
    let value: Double // 0...1
    var tint: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(tint).frame(width: max(value > 0 ? height : 0, geo.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

/// Bar made of coloured segments, e.g. tokens per provider.
struct StackedBar: View {
    let segments: [(value: Double, color: Color)]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
            HStack(spacing: 2) {
                if segments.allSatisfy({ $0.value <= 0 }) {
                    Capsule().fill(Color.white.opacity(0.08))
                } else {
                    ForEach(Array(segments.enumerated()), id: \.offset) { item in
                        if item.element.value > 0 {
                            Capsule()
                                .fill(item.element.color)
                                .frame(width: max(height, (geo.size.width - CGFloat(segments.count) * 2) * CGFloat(item.element.value / total)))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Controls

struct ThemedButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        let foreground: Color
        switch kind {
        case .primary: fill = Theme.accent; foreground = .white
        case .secondary: fill = Theme.tile; foreground = Theme.text
        case .destructive: fill = Theme.red.opacity(0.15); foreground = Theme.red
        }
        return configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(kind == .secondary ? Theme.strokeStrong : Color.clear, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Dark inset text field look.
    func themedField(width: CGFloat? = 240) -> some View {
        self.textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.strokeStrong, lineWidth: 1))
    }

    func themedSwitch() -> some View {
        self.toggleStyle(.switch).labelsHidden().tint(Theme.accent).controlSize(.small)
    }

    func themedMenu() -> some View {
        self.pickerStyle(.menu).labelsHidden().fixedSize()
    }
}
