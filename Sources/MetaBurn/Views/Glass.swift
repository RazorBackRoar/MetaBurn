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
    private func materialBody(_ content: Content) -> some View {
        switch shape {
        case .rounded(let radius):
            stacked(
                content,
                shape: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
        case .capsule:
            stacked(content, shape: Capsule())
        }
    }

    @ViewBuilder
    private func stacked<S: InsettableShape>(_ content: Content, shape: S) -> some View {
        let fill = clear ? MetaBurnTheme.panelFill.opacity(0.55) : MetaBurnTheme.panelFill
        content
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                    .blendMode(.plusLighter)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear], startPoint: .top, endPoint: .center)
                    )
            }
            .overlay {
                shape.strokeBorder(MetaBurnTheme.hairline, lineWidth: 1)
            }
    }

    @ViewBuilder
    @available(macOS 26.0, *)
    private func glassBody(_ content: Content) -> some View {
        let base = clear ? Glass.clear : Glass.regular
        let glass = base.tint(tint).interactive(interactive)
        switch shape {
        case .rounded(let radius):
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content
                .background(MetaBurnTheme.panelFill, in: shape)
                .glassEffect(glass, in: shape)
        case .capsule:
            content
                .background(MetaBurnTheme.panelFill, in: Capsule())
                .glassEffect(glass, in: Capsule())
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
                .background(
                    MetaBurnTheme.panelFill,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
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
