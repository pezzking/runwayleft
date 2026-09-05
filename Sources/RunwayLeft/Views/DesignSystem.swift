import SwiftUI
import AppKit

// MARK: - Text Size Setting

/// User-selectable text scale. `small` matches the original layout; `medium`
/// (the default) and `large` grow every font and the popover width together so
/// labels never get squeezed back down by line limits.
enum TextSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 1.0
        case .medium: return 1.16
        case .large: return 1.34
        }
    }

    var popoverWidth: CGFloat {
        switch self {
        case .small: return 410
        case .medium: return 456
        case .large: return 510
        }
    }
}

// MARK: - Semantic Font Roles

enum FontRole {
    /// App title in the header.
    case hero
    /// Card titles.
    case title
    /// Primary row labels and big values.
    case headline
    /// Default body copy.
    case body
    /// Secondary details (reset times, account info).
    case caption
    /// Section eyebrow labels and tiny badges.
    case micro

    var baseSize: CGFloat {
        switch self {
        case .hero: return 16
        case .title: return 14
        case .headline: return 12.5
        case .body: return 11.5
        case .caption: return 10.5
        case .micro: return 9.5
        }
    }
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

struct AppFontModifier: ViewModifier {
    @Environment(\.textScale) private var scale
    let role: FontRole
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: role.baseSize * scale, weight: weight, design: design))
    }
}

extension View {
    /// Applies a font from the semantic scale, multiplied by the user's text size.
    func appFont(_ role: FontRole, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AppFontModifier(role: role, weight: weight, design: design))
    }
}

// MARK: - Design Tokens

enum MacTheme {
    // Brand colors
    static let claudePrimary = Color(red: 0.95, green: 0.48, blue: 0.22)
    static let claudeSecondary = Color(red: 0.88, green: 0.32, blue: 0.18)
    static let claudeGradient = LinearGradient(
        colors: [claudePrimary, claudeSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let codexPrimary = Color(red: 0.12, green: 0.78, blue: 0.54)
    static let codexSecondary = Color(red: 0.05, green: 0.60, blue: 0.55)
    static let codexGradient = LinearGradient(
        colors: [codexPrimary, codexSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentBlue = Color(red: 0.22, green: 0.52, blue: 0.95)
    static let accentPurple = Color(red: 0.58, green: 0.36, blue: 0.94)

    static let litellmPrimary = accentPurple
    static let litellmSecondary = Color(red: 0.42, green: 0.26, blue: 0.80)
    static let litellmGradient = LinearGradient(
        colors: [litellmPrimary, litellmSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Status colors
    static let success = Color(red: 0.20, green: 0.80, blue: 0.48)
    static let warning = Color(red: 0.98, green: 0.65, blue: 0.15)
    static let danger = Color(red: 0.95, green: 0.30, blue: 0.30)
    static let info = Color(red: 0.35, green: 0.62, blue: 0.98)

    // Surfaces
    static let cardFill = Color(NSColor.controlBackgroundColor).opacity(0.55)
    static let cardStroke = Color.primary.opacity(0.09)
    static let subtleFill = Color.primary.opacity(0.05)

    static let cornerRadius: CGFloat = 14
    static let innerRadius: CGFloat = 10
}

// MARK: - Section Eyebrow Label

struct Eyebrow: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .appFont(.micro, weight: .semibold)
                .tracking(0.8)
                .foregroundColor(.secondary)
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .appFont(.caption, weight: .medium)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Glass Card Container

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = MacTheme.innerRadius, padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MacTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(MacTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Brand Tinted Card

struct GlowingBrandCard<Content: View>: View {
    let brandGradient: LinearGradient
    let borderColor: Color
    let cornerRadius: CGFloat
    let content: Content

    init(brandGradient: LinearGradient, borderColor: Color, cornerRadius: CGFloat = MacTheme.cornerRadius, @ViewBuilder content: () -> Content) {
        self.brandGradient = brandGradient
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(MacTheme.cardFill)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(brandGradient.opacity(0.07))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [borderColor.opacity(0.5), borderColor.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: borderColor.opacity(0.10), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Capsule Pill

struct Pill: View {
    let text: String
    let color: Color
    var icon: String? = nil
    var filled: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .appFont(.micro, weight: .bold)
            }
            Text(text)
                .appFont(.micro, weight: .bold)
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(color.opacity(filled ? 0.16 : 0.0)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.75))
    }
}

// MARK: - Live Indicator

/// Static on purpose: a repeating animation keeps the popover's render loop
/// busy for as long as the view exists.
struct PulsingLiveBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(MacTheme.success)
                .frame(width: 6, height: 6)
                .shadow(color: MacTheme.success.opacity(0.6), radius: 2)

            Text("LIVE")
                .appFont(.micro, weight: .bold)
                .tracking(0.5)
                .foregroundColor(MacTheme.success)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(MacTheme.success.opacity(0.12)))
        .overlay(Capsule().strokeBorder(MacTheme.success.opacity(0.3), lineWidth: 0.75))
    }
}

// MARK: - Relative Time

/// "Updated 3 min ago" that re-renders every 30 seconds instead of every
/// second like `Text(_, style: .relative)`.
struct RelativeTimeText: View {
    let date: Date
    var prefix: String = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(prefix + Self.describe(from: date, to: context.date))
        }
    }

    static func describe(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<60: return "just now"
        case 60..<3600: return "\(seconds / 60) min ago"
        case 3600..<86_400: return "\(seconds / 3600) h ago"
        default: return "\(seconds / 86_400) d ago"
        }
    }
}

// MARK: - Progress Bar

struct ModernProgressBar: View {
    let valuePct: Double
    let accentGradient: LinearGradient
    let height: CGFloat

    init(valuePct: Double, accentGradient: LinearGradient, height: CGFloat = 7) {
        self.valuePct = valuePct
        self.accentGradient = accentGradient
        self.height = height
    }

    var clampedPct: Double {
        max(0, min(100, valuePct))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))

                if clampedPct > 0 {
                    Capsule()
                        .fill(accentGradient)
                        .frame(width: max(height, geo.size.width * CGFloat(clampedPct / 100.0)))
                        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                }
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: clampedPct)
    }
}

// MARK: - Segmented Tab Button

struct GlassSegmentButton: View {
    let title: String
    let icon: String
    var brandImage: NSImage? = nil
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.textScale) private var scale
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let brandImg = brandImage {
                    Image(nsImage: brandImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12 * scale, height: 12 * scale)
                } else {
                    Image(systemName: icon)
                        .appFont(.caption, weight: isSelected ? .bold : .medium)
                }

                Text(title)
                    .appFont(.caption, weight: isSelected ? .semibold : .medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .foregroundColor(isSelected ? .primary : .secondary)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(NSColor.controlAccentColor).opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color(NSColor.controlAccentColor).opacity(0.45), lineWidth: 0.75)
                            )
                            .shadow(color: Color(NSColor.controlAccentColor).opacity(0.18), radius: 4, x: 0, y: 2)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Height Measurement

/// Reports a view's rendered height whenever it changes.
struct HeightReader: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onChange(geo.size.height) }
                    .onChange(of: geo.size.height) { newValue in onChange(newValue) }
            }
        )
    }
}

extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(HeightReader(onChange: onChange))
    }
}

// MARK: - Vertical Resize Grip

/// A thin strip along the bottom edge of the popover. Dragging it sets a custom
/// popover height (leaving fit-to-content mode). Movement is measured in screen
/// coordinates, since the grip itself moves as the window grows.
struct ResizeGrip: View {
    @ObservedObject var manager: UsageManager

    @State private var dragStartHeight: CGFloat? = nil
    @State private var dragStartMouseY: CGFloat? = nil
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.primary.opacity(isHovered || dragStartHeight != nil ? 0.4 : 0.18))
                .frame(width: 44, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 14)
        .contentShape(Rectangle())
        .help(manager.popoverHeightMode == .fit ? "Drag to set a custom height" : "Drag to resize")
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeUpDown.set()
            } else if dragStartHeight == nil {
                NSCursor.arrow.set()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { _ in
                    let mouseY = NSEvent.mouseLocation.y
                    if dragStartHeight == nil {
                        dragStartHeight = manager.effectivePopoverHeight
                        dragStartMouseY = mouseY
                    }
                    guard let startHeight = dragStartHeight, let startY = dragStartMouseY else { return }
                    // Screen Y grows upward, so dragging down (smaller Y) makes the window taller.
                    manager.setPopoverHeight(startHeight + (startY - mouseY), persist: false)
                }
                .onEnded { _ in
                    manager.setPopoverHeight(manager.popoverHeight, persist: true)
                    dragStartHeight = nil
                    dragStartMouseY = nil
                    if !isHovered {
                        NSCursor.arrow.set()
                    }
                }
        )
    }
}
