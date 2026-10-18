import AppKit
import SwiftUI

/// BKDG identity: Tinta, Osso and Bordô, flat surfaces, corners of at most 4pt, no gradients or glow.
/// Values come from the BKDG design system (tokens.css); dark mode uses the lighter Bordô that reads on Tinta.
enum Theme {
    static let accent = Color(light: 0x611E2C, dark: 0xB33751)
    static let accentTint = accent.opacity(0.1)
    /// Osso, the light brand tone used on Bordô and Tinta surfaces.
    static let onAccent = Color(hex: 0xF1ECE2)
    /// The solid Bordô band behind the home banner, the same in both themes.
    static let hero = Color(hex: 0x611E2C)
    /// The lighter Bordô for accents on Tinta, such as the recording overlay (3.38:1, where the full Bordô gives 1.63:1).
    static let accentOnTinta = Color(hex: 0xB33751)

    static let background = Color(light: 0xFFFFFF, dark: 0x0A0A0A)
    static let sidebar = Color(light: 0xF7F7F7, dark: 0x111110)
    static let card = Color(light: 0xFFFFFF, dark: 0x151514)
    static let border = Color(light: 0xD9D5CC, dark: 0x2A2926)
    static let hover = Color(light: 0x0A0A0A, dark: 0xF1ECE2).opacity(0.05)
    static let text = Color(light: 0x0A0A0A, dark: 0xF1ECE2)
    static let secondary = Color(light: 0x4A4A45, dark: 0xBDB8AE)

    /// Sober status tones: a muted green for ready and the brand's ochre for anything pending.
    static let ready = Color(light: 0x3F6B4F, dark: 0x7FA88A)
    static let warn = Color(hex: 0x8A6E4B)

    static let radius: CGFloat = 4

    /// Zilla Slab, the display face. Medium by default: the slab is wide and dark, so lower the weight before the size.
    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "ZillaSlab-Italic" : "ZillaSlab-Medium", size: size)
    }

    /// IBM Plex Sans, the body face.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .medium: .custom("IBMPlexSans-Medium", size: size)
        case .semibold: .custom("IBMPlexSans-SemiBold", size: size)
        case .bold, .heavy, .black: .custom("IBMPlexSans-Bold", size: size)
        default: .custom("IBMPlexSans", size: size)
        }
    }

    /// IBM Plex Mono, for labels (uppercase, tracked 0.08em) and key caps.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        switch weight {
        case .regular, .light: .custom("IBMPlexMono", size: size)
        case .semibold, .bold: .custom("IBMPlexMono-SemiBold", size: size)
        default: .custom("IBMPlexMono-Medium", size: size)
        }
    }
}

/// The app mark: the BKDG Observador (the official vector from brand-mark.svg, not redrawn) with three voice waves,
/// the same composition as Resources/Icons/app-icon.svg.
struct BrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        // The composition lives in the icon's 1024 space: x 190...716, y 262...762.
        let box = CGRect(x: 190, y: 262, width: 526, height: 500)
        let scale = min(rect.width / box.width, rect.height / box.height)
        let origin = CGPoint(x: rect.midX - box.midX * scale, y: rect.midY - box.midY * scale)
        func icon(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        // The dog's native coordinates, placed at x 430, y 262, 500 tall.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { icon(430 + (x - 428.4) * 500 / 252, 262 + (y - 50.4) * 500 / 252) }

        var path = Path()
        path.move(to: p(512.95, 219.73))
        path.addCurve(to: p(510.21, 213.79), control1: p(512.95, 219.73), control2: p(510.77, 217.28))
        path.addCurve(to: p(509.94, 209.64), control1: p(509.90, 211.87), control2: p(509.94, 209.64))
        path.addCurve(to: p(494.69, 188.77), control1: p(509.94, 196.71), control2: p(505.73, 190.73))
        path.addLine(to: p(467.75, 181.53))
        path.addCurve(to: p(440.79, 161.81), control1: p(456.00, 178.96), control2: p(447.02, 172.43))
        path.addLine(to: p(428.98, 141.70))
        path.addCurve(to: p(434.41, 129.83), control1: p(426.02, 136.66), control2: p(428.95, 130.84))
        path.addLine(to: p(466.18, 123.36))
        path.addCurve(to: p(491.81, 114.97), control1: p(483.47, 119.70), control2: p(489.75, 118.40))
        path.addLine(to: p(498.41, 109.29))
        path.addCurve(to: p(512.68, 101.20), control1: p(502.70, 105.60), control2: p(507.54, 102.86))
        path.addLine(to: p(538.59, 92.82))
        path.addCurve(to: p(569.51, 56.52), control1: p(546.50, 90.27), control2: p(565.32, 64.70))
        path.addLine(to: p(572.52, 50.42))
        path.addLine(to: p(572.52, 302.39))
        path.closeSubpath()

        var waves = Path()
        let center = icon(430, 428)
        for radius in [80, 150, 220] as [CGFloat] {
            // Each arc is its own subpath: without the move, addArc joins it to the previous one with a line.
            let start = Angle.degrees(145)
            waves.move(to: CGPoint(x: center.x + radius * scale * cos(start.radians),
                                   y: center.y + radius * scale * sin(start.radians)))
            waves.addArc(center: center, radius: radius * scale,
                         startAngle: start, endAngle: .degrees(215), clockwise: false)
        }
        path.addPath(waves.strokedPath(StrokeStyle(lineWidth: 24 * scale)))
        return path
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Layout

/// Scrolling page with consistent margins and a readable max width.
struct Page<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .padding(.horizontal, 44)
            .padding(.top, 40)
            .padding(.bottom, 48)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }
}

/// Title with an optional italic Bordô accent in the display face.
struct PageHeader: View {
    let title: String
    var accent: String?
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text(title) + Text(accent.map { " \($0)" } ?? "").italic().foregroundColor(Theme.accent))
                .font(Theme.display(34))
                .foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// A titled group of rows on a card, used by the settings-style pages.
struct SectionCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(Theme.mono(11, .medium))
                    .tracking(0.88)
                    .foregroundStyle(Theme.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .card(padding: 0)
            if let footer {
                Text(footer)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One row inside a `SectionCard`.
struct SettingRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var divider = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Theme.text)
                    if let detail {
                        Text(detail).font(Theme.body(12)).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if divider { Divider().overlay(Theme.border).padding(.leading, 16) }
        }
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }
}

// MARK: - Controls

struct KeyCaps: View {
    let keys: [String]
    var onAccent = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(Theme.mono(11, .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(onAccent ? Theme.onAccent.opacity(0.18) : Theme.accentTint))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(onAccent ? Theme.onAccent.opacity(0.35) : Theme.accent.opacity(0.3)))
                    .foregroundStyle(onAccent ? Theme.onAccent : Theme.accent)
            }
        }
        .fixedSize()
    }
}

struct Chip: View {
    let title: String
    var systemImage: String?
    var keys: [String]?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).foregroundStyle(Theme.accent) }
                Text(title).foregroundStyle(Theme.text)
                if let keys { KeyCaps(keys: keys) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(hovering ? Theme.accentTint : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(hovering ? Theme.accent.opacity(0.4) : Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Filled blue pill, the primary action style.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// Subtle outlined pill for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(configuration.isPressed ? Theme.hover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }
}

/// Plain text field drawn inside cards.
struct InlineField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.background))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            .onSubmit(onSubmit)
    }
}

/// Wraps its children onto new lines when a row runs out of width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
