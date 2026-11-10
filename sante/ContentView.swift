import SwiftUI
import ImageIO

struct ContentView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var selectedTab: HomeTab = .triage
    @State private var tourStep = 0
    @State private var showTour = false
    @State private var activeSheet: HomeSheet?
    @AppStorage("sante.didSeeHomeTour") private var didSeeHomeTour = false

    var body: some View {
        ZStack(alignment: .bottom) {
            SanteBackground()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 8)

                Spacer()

                focus
                    .id(selectedTab)
                    .transition(.opacity.combined(with: .offset(y: 12)))

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 90)

            tabBar
                .padding(.bottom, 14)
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.25), value: selectedTab)
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if showTour {
                HomeTourOverlay(step: $tourStep, anchors: anchors) {
                    withAnimation(.easeOut(duration: 0.2)) { showTour = false }
                    didSeeHomeTour = true
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            guard !didSeeHomeTour else { return }
            tourStep = 0
            showTour = true
        }
        .sheet(item: $activeSheet) { destination in
            Group {
                switch destination {
                case .profile:
                    PatientProfileView(accountStore: accountStore)
                case .documents:
                    PatientProfileView(accountStore: accountStore, focusDocuments: true)
                case .assistant:
                    AssistantChatView { report in
                        selectedTab = .consult
                        activeSheet = .appointment(report)
                    }
                case .appointment(let report):
                    AppointmentBookingView(report: report, patient: accountStore.currentUser)
                }
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 14))
                    .foregroundStyle(Sante.inkSoft)
                Text(accountStore.currentUser?.firstName ?? "Olá")
                    .font(Sante.display(26))
                    .foregroundStyle(Sante.ink)
            }
            Spacer()
            Button { activeSheet = .profile } label: { profileAvatar }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir meu perfil")
                .anchorPreference(key: TourAnchorKey.self, value: .bounds) { [.profile: $0] }
        }
    }

    private var profileAvatar: some View {
        Group {
            if let url = accountStore.currentUser.flatMap({ accountStore.profilePhotoURL(for: $0) }),
               let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(accountStore.currentUser?.initials ?? "S")
                    .font(Sante.title(17))
                    .foregroundStyle(Sante.ink)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .contentShape(Circle())
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Bom dia,"
        case 12..<18: "Boa tarde,"
        default: "Boa noite,"
        }
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: selectedTab.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Sante.primary)
                .frame(width: 64, height: 64)
                .background(.white, in: Circle())

            Text(selectedTab.headline)
                .font(Sante.display(34))
                .tracking(-0.8)
                .foregroundStyle(Sante.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(selectedTab.message)
                .font(.system(size: 16))
                .foregroundStyle(Sante.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                switch selectedTab {
                case .triage: activeSheet = .assistant
                case .consult: activeSheet = .appointment(nil)
                case .records: activeSheet = .documents
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedTab.cta)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(SantePrimaryButtonStyle())
            .padding(.top, 8)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(HomeTab.allCases) { tab in
                let isOn = tab == selectedTab
                Button { selectedTab = tab } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isOn ? .white : Sante.inkSoft)
                        .frame(width: 64, height: 48)
                        .background { if isOn { Capsule().fill(Sante.ink) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(5)
        .background(.white.opacity(0.9), in: Capsule())
        .shadow(color: Sante.ink.opacity(0.10), radius: 18, y: 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedTab)
        .anchorPreference(key: TourAnchorKey.self, value: .bounds) { [.tabBar: $0] }
    }
}

private enum HomeTab: Int, CaseIterable, Identifiable {
    case triage, consult, records
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .triage: "Triagem"
        case .consult: "Consulta"
        case .records: "Prontuário"
        }
    }
    var icon: String {
        switch self {
        case .triage: "text.bubble.fill"
        case .consult: "calendar"
        case .records: "folder.fill"
        }
    }
    var headline: String {
        switch self {
        case .triage: "Como você está\nse sentindo?"
        case .consult: "Solicite uma\nconsulta."
        case .records: "Seus exames\ne receitas."
        }
    }
    var message: String {
        switch self {
        case .triage: "Uma avaliação rápida com IA."
        case .consult: "Escolha a especialidade, a data e o horário e envie seu pedido por e-mail."
        case .records: "Veja seus dados de saúde e documentos salvos."
        }
    }
    var cta: String {
        switch self {
        case .triage: "Iniciar triagem"
        case .consult: "Solicitar consulta"
        case .records: "Abrir meus documentos"
        }
    }
}

private enum HomeSheet: Identifiable {
    case profile
    case documents
    case assistant
    case appointment(String?)

    var id: String {
        switch self {
        case .profile: "profile"
        case .documents: "documents"
        case .assistant: "assistant"
        case .appointment(let report): "appointment-\(report?.hashValue ?? 0)"
        }
    }
}

private enum TourTarget: Hashable {
    case profile, tabBar
}

private struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct HomeTourStep {
    let title: String
    let message: String
    let target: TourTarget
}

private struct HomeTourOverlay: View {
    @Binding var step: Int
    let anchors: [TourTarget: Anchor<CGRect>]
    let onFinish: () -> Void

    private let steps = [
        HomeTourStep(title: "Bem-vinda ao Sante", message: "Toque na sua foto no alto da tela para completar seu perfil e guardar informações importantes para o atendimento.", target: .profile),
        HomeTourStep(title: "Navegue por aqui", message: "Triagem, consulta e prontuário ficam na barra inferior.", target: .tabBar)
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let current = steps[step]
            let hole = anchors[current.target].map { proxy[$0].insetBy(dx: -8, dy: -8) }

            ZStack {
                TourDimmer(hole: hole)
                    .fill(Sante.ink.opacity(0.78), style: FillStyle(eoFill: true))

                VStack(spacing: 0) {
                    if let hole, current.target == .profile {
                        Spacer().frame(height: hole.maxY + 14)
                        tourCard
                        Spacer(minLength: 0)
                    } else if let hole {
                        Spacer(minLength: 0)
                        tourCard
                        Spacer().frame(height: max(size.height - hole.minY + 14, 0))
                    } else {
                        Spacer()
                        tourCard
                        Spacer()
                    }
                }
                .frame(maxWidth: min(size.width - 40, 340))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }
            .frame(width: size.width, height: size.height)
            .animation(.easeInOut(duration: 0.24), value: step)
        }
        .ignoresSafeArea()
        .zIndex(10)
    }

    private var tourCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(steps[step].title)
                .font(Sante.title(19))
                .foregroundStyle(Sante.ink)
            Text(steps[step].message)
                .font(.system(size: 14))
                .foregroundStyle(Sante.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Pular", action: onFinish)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Sante.inkSoft)
                    .buttonStyle(.plain)
                Spacer()
                Button(step == steps.count - 1 ? "Entendi" : "Próximo") {
                    if step == steps.count - 1 { onFinish() } else { step += 1 }
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 40)
                .background(Sante.ink, in: Capsule())
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

private struct TourDimmer: Shape {
    let hole: CGRect?
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if let hole {
            let radius = min(hole.width, hole.height) / 2
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}

#Preview {
    ContentView(accountStore: AccountStore())
}
