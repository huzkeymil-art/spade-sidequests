import SwiftUI
import UIKit

// Spade's look, in SwiftUI.
//
// The layout follows iPhone conventions. The material is Spade's own: corners
// are cut ("notched") instead of rounded, and shading is made of dot patterns
// instead of blur, to match the chunky 3D scene.

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

enum Ink {
    static let ink = Color(hex: 0x0d0f0c)
    static let loam = Color(hex: 0x171a14)
    static let loam2 = Color(hex: 0x20241c)
    static let moss = Color(hex: 0x2e3626)
    static let moss2 = Color(hex: 0x4a563b)
    static let bone = Color(hex: 0xe6dfc8)
    static let dim = Color(hex: 0xa3a591)
    /// The quietest colour still allowed for words: 4.9 to 1 against the background.
    static let faint = Color(hex: 0x7f8373)
    /// For decoration only, never for words anyone needs to read.
    static let ghost = Color(hex: 0x575b4f)
    static let lantern = Color(hex: 0xf2b544)
    static let verdigris = Color(hex: 0x5fb39a)
    static let rust = Color(hex: 0xd9634a)
    static let moonsteel = Color(hex: 0x7aa7d9)
}

extension Rarity {
    var color: Color {
        switch self {
        case .common: return Ink.bone
        case .uncommon: return Ink.verdigris
        case .rare: return Ink.moonsteel
        case .mythic: return Ink.lantern
        }
    }

    /// The colour of light each rarity gives off when dug up.
    var light: RGB {
        switch self {
        case .common: return rgb("#e6dfc8")
        case .uncommon: return rgb("#5fe0b0")
        case .rare: return rgb("#7ab8ff")
        case .mythic: return rgb("#ffc24a")
        }
    }
}

/// The three typefaces. Sizes follow the phone's text-size setting (Dynamic Type).
enum Typeface {
    /// A blackletter drawn on a pixel grid: the logo, titles, big numbers.
    static func display(_ size: CGFloat) -> Font {
        .custom("Jacquard24-Regular", size: size, relativeTo: .title)
    }

    /// A pixel sans: numbers and small capital labels.
    static func label(_ size: CGFloat = 15) -> Font {
        .custom("Jersey15-Regular", size: size, relativeTo: .footnote)
    }

    /// An old printing-press serif: quest text and descriptions.
    static func text(_ size: CGFloat = 17) -> Font {
        .custom("IM_FELL_English_Roman", size: size, relativeTo: .body)
    }

    static func italic(_ size: CGFloat = 17) -> Font {
        .custom("IM_FELL_English_Italic", size: size, relativeTo: .body)
    }
}

extension View {
    /// Small capital label text.
    func caps(_ color: Color = Ink.bone, size: CGFloat = 15) -> some View {
        font(Typeface.label(size))
            .textCase(.uppercase)
            .tracking(1.3)
            .foregroundStyle(color)
    }

    /// A panel with its corners cut off and a one-pixel edge.
    func plate(fill: Color = Ink.loam, edge: Color = Ink.moss, notch: CGFloat = 6) -> some View {
        background(Notched(notch: notch).fill(fill))
            .overlay(Notched(notch: notch).strokeBorder(edge, lineWidth: 1))
    }

    /// The standard look for a sheet that slides up over the app.
    func spadeSheet(_ detents: Set<PresentationDetent> = [.large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(Ink.loam)
            .dynamicTypeSize(.xSmall ... .xxxLarge)
            .preferredColorScheme(.dark)
    }
}

/// A rectangle with its corners cut off at 45 degrees.
struct Notched: InsettableShape {
    var notch: CGFloat = 6
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let n = max(0, min(notch - inset * 0.4, min(r.width, r.height) / 2))
        var path = Path()
        path.move(to: CGPoint(x: r.minX + n, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - n, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + n))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - n))
        path.addLine(to: CGPoint(x: r.maxX - n, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + n, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - n))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + n))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> Notched {
        var copy = self
        copy.inset += amount
        return copy
    }
}

// MARK: - Dot patterns

/// A repeating pattern of square dots: a quarter, half or three-quarters filled.
struct Dots: View {
    var color: Color
    /// 1, 2 or 3 dots out of every 4.
    var density: Int = 2
    @EnvironmentObject private var stage: StageController

    var body: some View {
        Image(uiImage: DotPattern.image(color: UIColor(color), density: density, pixel: stage.pixelSize))
            .interpolation(.none)
            .resizable(resizingMode: .tile)
            .accessibilityHidden(true)
    }
}

@MainActor
enum DotPattern {
    private static var cache: [String: UIImage] = [:]

    static func image(color: UIColor, density: Int, pixel: CGFloat) -> UIImage {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = "\(Int(r * 255))-\(Int(g * 255))-\(Int(b * 255))-\(density)-\(Int(pixel * 100))"
        if let hit = cache[key] { return hit }
        // A 2 x 2 grid. Which cells are filled: one, the two on the diagonal, or three.
        let filled: [Bool]
        switch density {
        case 1: filled = [true, false, false, false]
        case 3: filled = [true, true, false, true]
        default: filled = [true, false, false, true]
        }
        var pixels = [UInt8](repeating: 0, count: 16)
        for cell in 0..<4 where filled[cell] {
            pixels[cell * 4] = UInt8(r * 255)
            pixels[cell * 4 + 1] = UInt8(g * 255)
            pixels[cell * 4 + 2] = UInt8(b * 255)
            pixels[cell * 4 + 3] = 255
        }
        // The picture's scale makes each dot exactly one chunky scene pixel wide.
        let image = Textures.image(fromRGBA: pixels, width: 2, height: 2, scale: 1 / max(pixel, 0.5))
        cache[key] = image
        return image
    }
}

/// Three bands of dots, each denser than the last: Spade's version of a soft fade.
struct DitherFade: View {
    var color: Color = Ink.ink
    @EnvironmentObject private var stage: StageController

    /// How tall the fade is, for a given chunky-pixel size.
    static func height(pixel: CGFloat) -> CGFloat { pixel * 2 * 4 * 3 }

    var body: some View {
        let band = stage.pixelSize * 2 * 4
        VStack(spacing: 0) {
            Dots(color: color, density: 1).frame(height: band)
            Dots(color: color, density: 2).frame(height: band)
            Dots(color: color, density: 3).frame(height: band)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Buttons

struct PlateButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, danger }
    var kind: Kind = .plain
    /// Stretch to the full width available.
    var block = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, kind: kind, block: block)
    }

    private struct Face: View {
        let configuration: Configuration
        let kind: Kind
        let block: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let pressed = configuration.isPressed
            let fill: Color = !enabled ? Ink.loam : kind == .primary ? (pressed ? Color(hex: 0xc9922c) : Ink.lantern) : (pressed ? Ink.moss : Ink.loam2)
            let edge: Color = !enabled ? Ink.moss : kind == .primary ? fill : kind == .danger ? Ink.rust : Ink.moss2
            let text: Color = !enabled ? Ink.ghost : kind == .primary ? Ink.ink : kind == .danger ? Ink.rust : Ink.bone
            configuration.label
                .font(Typeface.label())
                .textCase(.uppercase)
                .tracking(1.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(text)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .frame(maxWidth: block ? .infinity : nil, minHeight: 50)
                .plate(fill: fill, edge: edge, notch: 8)
                .offset(y: pressed && enabled ? 2 : 0)
        }
    }
}

/// A pill-shaped option that is either chosen or not.
struct Chip: View {
    let title: String
    var icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { PropIcon(name: icon, size: 18, res: 18) }
                Text(title).caps(selected ? Ink.bone : Ink.dim)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .plate(fill: selected ? Ink.loam2 : Ink.ink, edge: selected ? Ink.bone : Ink.moss, notch: 6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A square of colour to pick.
struct Swatch: View {
    let color: Color
    let selected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Notched(notch: 4).fill(color)
                .padding(4)
                .frame(width: 44, height: 44)
                .plate(fill: Ink.loam, edge: selected ? Ink.bone : Ink.moss, notch: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An on/off switch in Spade's style, with a label. The whole row is the button.
struct ToggleRow: View {
    let title: String
    var note: String?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            Feedback.select()
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(Typeface.text()).foregroundStyle(Ink.bone)
                    if let note { Text(note).caps(Ink.faint) }
                }
                Spacer(minLength: 8)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Color.clear
                    Rectangle().fill(isOn ? Ink.verdigris : Ink.faint).frame(width: 19, height: 19).padding(.horizontal, 6)
                }
                .frame(width: 51, height: 31)
                .plate(fill: Ink.ink, edge: isOn ? Ink.verdigris : Ink.moss2, notch: 5)
                .animation(.easeOut(duration: 0.12), value: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A row inside a grouped list: at least 52 points tall, darkening while pressed.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(configuration.isPressed ? Ink.moss : Color.clear)
    }
}

/// A group of rows on one plate (an iOS "inset grouped" list). Put a `Hairline` between rows.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .plate(fill: Ink.loam, edge: Ink.moss, notch: 9)
            .clipShape(Notched(notch: 9))
    }
}

/// A one-pixel dividing line.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Ink.moss).frame(height: 1).accessibilityHidden(true)
    }
}

/// A heading above a group.
struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .caps(Ink.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.bottom, 9)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A small right-pointing arrow for rows that open something.
struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Ink.faint)
            .accessibilityHidden(true)
    }
}

// MARK: - Gauge

/// A notched bar that shows progress.
struct NotchGauge: View {
    var value: Double
    var total: Double
    var height: CGFloat = 9
    var ticks = true

    var body: some View {
        GeometryReader { proxy in
            let fraction = total > 0 ? min(1, max(0, value / total)) : 0
            ZStack(alignment: .leading) {
                Ink.loam
                Dots(color: Ink.moss2, density: 1)
                Rectangle().fill(Ink.verdigris).frame(width: proxy.size.width * fraction)
                if ticks {
                    HStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { _ in
                            Color.clear.overlay(alignment: .trailing) { Ink.ink.frame(width: 1) }
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.6), value: fraction)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(value)) of \(Int(total))")
    }
}

// MARK: - Icons

/// An item's icon: a tiny photo of its 3D model.
struct ItemIcon: View {
    let id: String
    var size: CGFloat

    var body: some View {
        Image(uiImage: IconForge.shared.item(id))
            .interpolation(.none)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// One of the small prop icons (tabs, quest kinds, and so on).
struct PropIcon: View {
    let name: String
    var size: CGFloat
    var res: Int = 22

    var body: some View {
        Image(uiImage: IconForge.shared.prop(name, res: res))
            .interpolation(.none)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The hero's face as they currently look.
struct PortraitIcon: View {
    let hero: HeroSave
    let gear: [String: String]
    var size: CGFloat

    var body: some View {
        Image(uiImage: IconForge.shared.portrait(look: HeroLook(hero), gear: gear))
            .interpolation(.none)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A square slot that holds an item icon, or stands empty.
/// It is always as wide as the space it is given, whatever is inside.
struct SlotFrame<Content: View>: View {
    var edge: Color = Ink.moss
    var fill: Color = Ink.loam
    @ViewBuilder var content: Content

    var body: some View {
        Notched(notch: 7)
            .fill(fill)
            .overlay(Notched(notch: 7).strokeBorder(edge, lineWidth: 1))
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
    }
}

// MARK: - Layout

/// Lays children out left to right, wrapping onto new lines when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map { $0.width }.max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var items: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width && !row.items.isEmpty {
                rows.append(Row(items: [index], y: row.y + row.height + spacing, width: size.width, height: size.height))
            } else {
                row.items.append(index)
                row.width = needed
                row.height = max(row.height, size.height)
                rows[rows.count - 1] = row
            }
        }
        return rows
    }
}

/// The room the floating tab bar takes at the bottom, so lists can leave space for it.
private struct DockSpaceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 86
}

extension EnvironmentValues {
    var dockSpace: CGFloat {
        get { self[DockSpaceKey.self] }
        set { self[DockSpaceKey.self] = newValue }
    }
}
