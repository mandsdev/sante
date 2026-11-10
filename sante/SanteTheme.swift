import SwiftUI

enum Sante {
    static let appName = "Sante"

    static let ink        = Color(red: 0.020, green: 0.204, blue: 0.153)
    static let inkSoft    = Color(red: 0.235, green: 0.353, blue: 0.310)
    static let primary    = Color(red: 0.047, green: 0.361, blue: 0.267)
    static let mint       = Color(red: 0.851, green: 0.922, blue: 0.878)
    static let mintDeep   = Color(red: 0.690, green: 0.851, blue: 0.761)
    static let cream      = Color(red: 0.976, green: 0.980, blue: 0.965)
    static let paper      = cream
    static let coral      = Color(red: 0.690, green: 0.176, blue: 0.145)
    static let amber      = Color(red: 0.961, green: 0.682, blue: 0.290)
    static let sky        = Color(red: 0.384, green: 0.635, blue: 0.851)
    static let success    = Color(red: 0.090, green: 0.420, blue: 0.267)
    static let surface    = Color.white
    static let stroke     = Color(red: 0.020, green: 0.204, blue: 0.153).opacity(0.10)

    static let radiusS: CGFloat = 12
    static let radiusM: CGFloat = 18
    static let radiusL: CGFloat = 26

    static func display(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func title(_ size: CGFloat = 19) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 12.5, weight: .medium)
    static let eyebrow = Font.system(size: 11, weight: .bold, design: .rounded)
}

struct SanteBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Sante.mint, Sante.cream], startPoint: .top, endPoint: .bottom)

            Circle()
                .fill(Sante.mintDeep.opacity(0.55))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: drift ? 110 : 70, y: drift ? -300 : -260)

            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: drift ? -120 : -80, y: drift ? -120 : -160)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift.toggle() }
        }
        .accessibilityHidden(true)
    }
}

struct SanteCard: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: Sante.radiusM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Sante.radiusM, style: .continuous).stroke(.white, lineWidth: 1))
            .shadow(color: Sante.ink.opacity(0.06), radius: 18, y: 8)
    }
}

extension View {
    func santeCard(padding: CGFloat = 18) -> some View { modifier(SanteCard(padding: padding)) }

    func santeField(isFocused: Bool = false, isValid: Bool? = nil) -> some View {
        let border: Color = {
            if isValid == false { return Sante.coral.opacity(0.7) }
            if isFocused { return Sante.primary.opacity(0.6) }
            return Sante.stroke
        }()
        return self
            .font(Sante.body)
            .foregroundStyle(Sante.ink)
            .padding(.horizontal, 15)
            .frame(height: 52)
            .background(.white, in: RoundedRectangle(cornerRadius: Sante.radiusS, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Sante.radiusS, style: .continuous)
                    .stroke(border, lineWidth: isFocused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct SantePrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(enabled ? .white : Sante.inkSoft)
            .background(
                enabled
                    ? AnyShapeStyle(LinearGradient(colors: [Sante.primary, Sante.ink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Sante.cream),
                in: RoundedRectangle(cornerRadius: Sante.radiusM - 2, style: .continuous)
            )
            .shadow(color: Sante.ink.opacity(enabled ? 0.22 : 0), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SanteGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Sante.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.white.opacity(configuration.isPressed ? 0.9 : 0.6), in: RoundedRectangle(cornerRadius: Sante.radiusM - 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Sante.radiusM - 2, style: .continuous).stroke(Sante.stroke))
    }
}

struct SanteIconButton: View {
    let systemName: String
    var label: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Sante.ink)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.85), in: Circle())
                .overlay(Circle().stroke(Sante.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct SanteLogo: View {
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: size * 0.55) {
            Image(systemName: "heart.text.square.fill")
                .symbolRenderingMode(.hierarchical)
            Text("SANTE")
                .tracking(size * 0.145)
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .foregroundStyle(Sante.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Sante.appName)
    }
}

struct SanteEmergencyLink: View {
    var body: some View {
        Link(destination: URL(string: "tel:192")!) {
            Label("Emergência? Ligue 192", systemImage: "phone.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Sante.coral)
        }
        .accessibilityLabel("Em caso de emergência, ligar para o SAMU, 192")
    }
}

struct SanteErrorText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Sante.coral)
            .fixedSize(horizontal: false, vertical: true)
    }
}
