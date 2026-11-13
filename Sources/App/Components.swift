import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Atmosphere: the background that says "photo" or "video" without reading a word

struct Atmosphere: View {
    let theme: TabTheme
    let tab: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                theme.base
                // Two soft light sources: the accent top-left, the haze bottom-right.
                RadialGradient(colors: [theme.accent.opacity(0.22), .clear], center: .init(x: 0.12, y: 0.0),
                               startRadius: 0, endRadius: geo.size.width * 0.75)
                RadialGradient(colors: [theme.haze.opacity(0.55), .clear], center: .init(x: 1.0, y: 1.0),
                               startRadius: 0, endRadius: geo.size.width * 0.8)
                // The big faint symbol: an aperture for photos, a film strip for videos.
                Image(systemName: theme.symbol)
                    .font(.system(size: geo.size.width * 0.78, weight: .ultraLight))
                    .foregroundStyle(LinearGradient(colors: [theme.accent.opacity(0.10), .white.opacity(0.015)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .rotationEffect(.degrees(tab == .photos ? -12 : 8))
                    .offset(x: geo.size.width * 0.30, y: geo.size.height * 0.18)
                    .id(tab)   // crossfade between symbols
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                // Fine grain so the gradients never band.
                Canvas { ctx, size in
                    var rng = SplitMix(seed: 7)
                    for _ in 0..<Int(size.width * size.height / 900) {
                        let x = Double(rng.next() % UInt64(max(1, size.width)))
                        let y = Double(rng.next() % UInt64(max(1, size.height)))
                        ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.025)))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

struct SplitMix { var s: UInt64; init(seed: UInt64) { s = seed }
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }

// MARK: - Glass card

struct Glass: ViewModifier {
    let theme: TabTheme
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [theme.surface.opacity(0.78), theme.surface.opacity(0.52)],
                                         startPoint: .top, endPoint: .bottom))
                    .background(.ultraThinMaterial.opacity(0.35), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }
}
extension View { func glass(_ t: TabTheme, radius: CGFloat = 18) -> some View { modifier(Glass(theme: t, radius: radius)) } }

// MARK: - Tab switcher: a pill whose highlight slides and changes colour

struct TabSwitcher: View {
    @Binding var tab: AppTab
    let theme: TabTheme
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { t in
                let on = t == tab
                Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { tab = t } } label: {
                    HStack(spacing: 7) {
                        Image(systemName: t == .photos ? "photo" : "play.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(t == .photos ? L.photos : L.videos).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(on ? theme.ink : Ink.body)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background {
                        if on {
                            Capsule().fill(LinearGradient(colors: [theme.accentHi, theme.accent], startPoint: .top, endPoint: .bottom))
                                .shadow(color: theme.accent.opacity(0.55), radius: 12)
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Ink.hairline))
    }
}

// MARK: - Animated figure ("4,0 MB → 0,9 MB · −78 %")

/// A number that counts up from 0 when it changes (Animatable, works on macOS 13).
struct CountingText: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View { Text(format(value)).monospacedDigit() }
}

struct SavingsHero: View {
    let before: Int64
    let after: Int64
    let theme: TabTheme
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { before > 0 ? max(0, 1 - Double(after) / Double(before)) : 0 }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
                Circle().trim(from: 0, to: shown)
                    .stroke(AngularGradient(colors: [theme.accent, theme.accentHi, theme.accent], center: .center),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: theme.accent.opacity(0.6), radius: 8)
                CountingText(value: shown * 100) { "−\(Int($0.rounded())) %" }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.accentHi)
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.saved).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Ink.label)
                HStack(spacing: 8) {
                    Text(formatBytes(before)).foregroundStyle(Ink.body).strikethrough(color: Ink.label)
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.label)
                    CountingText(value: Double(before) - (Double(before - after) * shown / max(fraction, 0.0001))) { formatBytes(Int64($0)) }
                        .foregroundStyle(Ink.title)
                }
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .onAppear { animate() }
        .onChange(of: after) { _ in shown = 0; animate() }
    }

    private func animate() {
        if reduceMotion { shown = fraction; return }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.4)) { shown = fraction }
    }
}

// MARK: - Drop zone with a living border

struct DropZone<Content: View>: View {
    let theme: TabTheme
    @Binding var targeted: Bool
    let onDrop: ([URL]) -> Void
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !targeted || reduceMotion)) { tl in
            let angle = targeted && !reduceMotion ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 * 360 : 0
            content
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(RadialGradient(colors: [theme.accent.opacity(targeted ? 0.20 : 0.07), .clear],
                                             center: .center, startRadius: 0, endRadius: 320))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            targeted
                            ? AnyShapeStyle(AngularGradient(colors: [theme.accent, theme.accentHi.opacity(0.2), theme.haze, theme.accent],
                                                            center: .center, angle: .degrees(angle)))
                            : AnyShapeStyle(Color.white.opacity(0.16)),
                            style: StrokeStyle(lineWidth: targeted ? 2 : 1.2, dash: targeted ? [] : [6, 7]))
                )
                .scaleEffect(targeted && !reduceMotion ? 1.012 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: targeted)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            let lock = NSLock()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { lock.lock(); urls.append(url); lock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) { onDrop(urls) }
            return true
        }
    }
}

// MARK: - Chips (premium segmented choice)

struct Chip: View {
    let title: String
    var subtitle: String? = nil
    let on: Bool
    let theme: TabTheme
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                if let s = subtitle { Text(s).font(.system(size: 10.5)).foregroundStyle(on ? theme.accentHi.opacity(0.85) : Ink.label) }
            }
            .foregroundStyle(on ? Ink.title : (disabled ? Ink.label : Ink.lead))
            .frame(maxWidth: .infinity)
            .padding(.vertical, subtitle == nil ? 8 : 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(on ? theme.accent.opacity(0.16) : Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(on ? theme.accent.opacity(0.75) : Ink.hairline, lineWidth: 1)
            )
            .shadow(color: on ? theme.accent.opacity(0.25) : .clear, radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.easeOut(duration: 0.18), value: on)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(1.3).foregroundStyle(Ink.label)
    }
}

/// Primary call to action: dark ink on the glowing accent.
struct AccentButtonStyle: ButtonStyle {
    let theme: TabTheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Capsule().fill(LinearGradient(colors: [theme.accentHi, theme.accent], startPoint: .top, endPoint: .bottom)))
            .shadow(color: theme.accent.opacity(configuration.isPressed ? 0.2 : 0.45), radius: 14)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Ink.lead)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.05)))
            .overlay(Capsule().strokeBorder(Ink.hairline))
    }
}

// MARK: - Footer: signature + contact

struct Footer: View {
    let theme: TabTheme
    var body: some View {
        HStack(spacing: 6) {
            Text(L.designedBy).foregroundStyle(Ink.label)
            Text(Credits.author).fontWeight(.semibold).foregroundStyle(Ink.body)
            Spacer()
            Link(destination: Credits.mailURL) {
                HStack(spacing: 6) {
                    Image(systemName: "envelope")
                    Text(L.hireMe)
                }
            }
            .foregroundStyle(Ink.body)
            .help(Credits.email)
        }
        .font(.system(size: 11))
    }
}
