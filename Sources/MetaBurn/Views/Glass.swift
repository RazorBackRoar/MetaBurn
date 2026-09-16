import SwiftUI

private enum MetaBurnGlassShape {
    case rounded(CGFloat)
    case capsule
}

private struct MetaBurnGlassModifier: ViewModifier {
    var shape: MetaBurnGlassShape
    var tint: Color?
    var interactive: Bool
    var clear: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            glassBody(content)
        } else {
            materialBody(content)
        }
    }

    @ViewBuilder
    @available(macOS 26.0, *)
    private func glassBody(_ content: Content) -> some View {
        let base = clear ? Glass.clear : Glass.regular
        let glass = base.tint(tint).interactive(interactive)
        switch shape {
        case .rounded(let radius):
            content.glassEffect(
                glass, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule:
            content.glassEffect(glass, in: Capsule())
        }
    }

    @ViewBuilder
    private func materialBody(_ content: Content) -> some View {
        let fillOpacity = clear ? 0.28 : 1.0
        switch shape {
        case .rounded(let radius):
            content
                .background(
                    .ultraThinMaterial.opacity(fillOpacity),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                        .blendMode(.plusLighter)
                        .mask(
                            LinearGradient(
                                colors: [.white, .clear], startPoint: .top, endPoint: .center)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(MetaBurnTheme.hairline, lineWidth: 1)
                }
        case .capsule:
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                        .blendMode(.plusLighter)
                        .mask(
                            LinearGradient(
                                colors: [.white, .clear], startPoint: .top, endPoint: .center)
                        )
                }
                .overlay {
                    Capsule().strokeBorder(MetaBurnTheme.hairline, lineWidth: 1)
                }
        }
    }
}

extension View {
    func metaBurnGlass(
        cornerRadius: CGFloat = 14,
        tint: Color? = nil,
        interactive: Bool = false,
        clear: Bool = false
    ) -> some View {
        modifier(
            MetaBurnGlassModifier(
                shape: .rounded(cornerRadius),
                tint: tint,
                interactive: interactive,
                clear: clear
            )
        )
    }

    func metaBurnGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(
            MetaBurnGlassModifier(
                shape: .capsule, tint: tint, interactive: interactive, clear: false)
        )
    }
}

struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassEffect(
                    .regular.tint(MetaBurnTheme.accent).interactive(),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
        } else {
            PrimaryButtonStyle().makeBody(configuration: configuration)
        }
    }
}

struct GlassGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .opacity(configuration.isPressed ? 0.72 : 1)
        } else {
            GhostButtonStyle().makeBody(configuration: configuration)
        }
    }
}
