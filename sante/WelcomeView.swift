import SwiftUI
import Combine
#if os(iOS)
import CoreMotion
#endif

private enum WelcomeColors {
    static let background = Sante.mint
    static let purple = Sante.ink
    static let orange = Sante.ink
    static let secondary = Sante.inkSoft
}

private struct WelcomePage {
    let eyebrow: String
    let title: String
    let description: String
}

struct WelcomeView: View {
    @StateObject private var accountStore: AccountStore
    @State private var page = 0
    @State private var activeSheet: WelcomeSheet?
    private let previewOnboarding: Bool

    init(previewOnboarding: Bool = false) {
        self.previewOnboarding = previewOnboarding
        _accountStore = StateObject(wrappedValue: AccountStore())
    }

    private let pages = [
        WelcomePage(
            eyebrow: "CUIDADO QUE",
            title: "começa por você.",
            description: "Sua saúde, acompanhada com atenção em cada etapa."
        ),
        WelcomePage(
            eyebrow: "UMA TRIAGEM QUE",
            title: "escuta você.",
            description: "Conte o que está sentindo e leve um resumo pronto para o médico."
        ),
        WelcomePage(
            eyebrow: "SUA CONSULTA",
            title: "sem complicação.",
            description: "Escolha especialidade, data e horário e envie seu pedido em poucos toques."
        )
    ]

    var body: some View {
        Group {
            if accountStore.isAuthenticated && !previewOnboarding {
                ContentView(accountStore: accountStore)
            } else if !accountStore.hasRestoredSession && !previewOnboarding {
                SessionSplashView()
            } else {
                onboarding
            }
        }
        .animation(.easeInOut(duration: 0.25), value: accountStore.hasRestoredSession)
        .sheet(item: $activeSheet) { destination in
            switch destination {
            case .login:
                #if os(iOS)
                LoginView(accountStore: accountStore, onCreateAccount: { activeSheet = .signup })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                #else
                LoginView(accountStore: accountStore, onCreateAccount: { activeSheet = .signup })
                #endif
            case .signup:
                SignupView(accountStore: accountStore, onSignIn: { activeSheet = .login })
            }
        }
        .task { await accountStore.restoreRemoteSession() }
    }

    private var onboarding: some View {
        GeometryReader { geometry in
            ZStack {
                SanteBackground()

                LeafParallaxFrame(page: page)

                VStack(spacing: 0) {
                    SanteLogo()
                        .padding(.top, 18)

                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                            onboardingPage(item)
                                .tag(index)
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    #else
                    .tabViewStyle(.automatic)
                    #endif

                    VStack(spacing: 14) {
                        Button { activeSheet = .signup } label: {
                            Text("Começar")
                        }
                        .buttonStyle(SantePrimaryButtonStyle())

                        Button { activeSheet = .login } label: {
                            Text("Já tenho uma conta")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Sante.ink)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 44)

                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { index in
                            Circle()
                                .fill(index == page ? Sante.ink : Sante.ink.opacity(0.2))
                                .frame(width: 7, height: 7)
                                .animation(.easeOut(duration: 0.2), value: page)
                        }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom == 0 ? 18 : 10, 10))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Página \(page + 1) de \(pages.count)")
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func onboardingPage(_ item: WelcomePage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Text(item.eyebrow)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Sante.primary)

            Text(item.title)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(Sante.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Text(item.description)
                .font(.system(size: 17))
                .foregroundStyle(Sante.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.trailing, 30)

            Spacer()
                .frame(height: 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 44)
    }
}

private struct SessionSplashView: View {
    var body: some View {
        ZStack {
            SanteBackground()
            VStack(spacing: 18) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 54))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Sante.primary)
                SanteLogo()
                ProgressView()
                    .tint(Sante.primary)
                    .padding(.top, 6)
            }
        }
        .preferredColorScheme(.light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carregando sua conta")
    }
}

private enum WelcomeSheet: String, Identifiable {
    case login
    case signup

    var id: String { rawValue }
}

private struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountStore: AccountStore
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showPasswordReset = false
    @State private var showEmailConfirmation = false
    @FocusState private var focusedField: LoginField?
    let onCreateAccount: () -> Void

    private enum LoginField: Hashable {
        case email, password
    }

    private var canSubmit: Bool {
        SanteValidation.isValidEmail(email) && !password.isEmpty
    }

    var body: some View {
        ZStack {
            SanteBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 25) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(WelcomeColors.purple)
                                .frame(width: 42, height: 42)
                                .background(.white.opacity(0.8), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Voltar")
                        Spacer()
                        SanteLogo()
                    }
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Que bom ter você de volta")
                            .font(Sante.display(30))
                            .tracking(-0.5)
                            .foregroundStyle(WelcomeColors.purple)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Entre na sua conta para continuar cuidando da sua saúde.")
                            .font(.system(size: 15))
                            .foregroundStyle(WelcomeColors.secondary)
                            .lineSpacing(3)
                    }

                    VStack(alignment: .leading, spacing: 19) {
                        loginFieldTitle("E-mail")
                        HStack(spacing: 11) {
                            Image(systemName: "envelope")
                                .foregroundStyle(WelcomeColors.secondary)
                            TextField("seuemail@exemplo.com", text: $email)
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                                #if os(iOS)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                        }
                        .loginInput(isFocused: focusedField == .email)

                        VStack(alignment: .leading, spacing: 8) {
                            loginFieldTitle("Senha")
                            HStack(spacing: 11) {
                                Image(systemName: "lock")
                                    .foregroundStyle(WelcomeColors.secondary)
                                Group {
                                    if isPasswordVisible {
                                        TextField("Digite sua senha", text: $password)
                                    } else {
                                        SecureField("Digite sua senha", text: $password)
                                    }
                                }
                                .focused($focusedField, equals: .password)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
                                Button {
                                    isPasswordVisible.toggle()
                                } label: {
                                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                        .foregroundStyle(WelcomeColors.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isPasswordVisible ? "Ocultar senha" : "Mostrar senha")
                            }
                            .loginInput(isFocused: focusedField == .password)
                        }

                        Button {
                            focusedField = nil
                            showPasswordReset = true
                        } label: {
                            Text("Esqueci minha senha")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WelcomeColors.purple)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            focusedField = nil
                            Task {
                                switch await accountStore.signInRemote(email: email, password: password) {
                                case .signedIn:
                                    dismiss()
                                case .needsEmailConfirmation:
                                    showEmailConfirmation = true
                                case .failed(let error):
                                    alertTitle = "Não foi possível entrar"
                                    alertMessage = error
                                    showAlert = true
                                }
                            }
                        } label: {
                            if accountStore.isConnecting {
                                ProgressView().tint(.white)
                            } else {
                                HStack(spacing: 9) {
                                    Text("Acessar conta")
                                    Image(systemName: "arrow.right")
                                }
                            }
                        }
                        .buttonStyle(SantePrimaryButtonStyle(enabled: canSubmit && !accountStore.isConnecting))
                        .disabled(!canSubmit || accountStore.isConnecting)
                    }
                    .santeCard(padding: 21)

                    HStack(spacing: 5) {
                        Spacer(minLength: 0)
                        Text("Ainda não tem uma conta?")
                            .foregroundStyle(WelcomeColors.secondary)
                        Button("Cadastre-se", action: onCreateAccount)
                            .fontWeight(.bold)
                            .foregroundStyle(WelcomeColors.purple)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 14))
                    .padding(.bottom, 22)
                }
                .padding(.horizontal, 24)
            }
        }
        .sheet(isPresented: $showEmailConfirmation) {
            EmailConfirmationView(
                accountStore: accountStore,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                codeAlreadySent: false
            ) {
                showEmailConfirmation = false
                dismiss()
            }
            #if os(iOS)
            .presentationDetents([.large])
            #endif
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView(accountStore: accountStore, initialEmail: email) {
                showPasswordReset = false
                dismiss()
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .preferredColorScheme(.light)
    }

    private func loginFieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WelcomeColors.purple)
    }
}

private struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountStore: AccountStore
    let onSuccess: () -> Void

    private enum Step { case email, code, done }
    private enum Field: Hashable { case email, code, password }

    @State private var step: Step = .email
    @State private var email: String
    @State private var code = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var errorMessage: String?
    @State private var resendAvailableAt = Date.distantPast
    @FocusState private var focusedField: Field?

    private let resendInterval: TimeInterval = 60

    init(accountStore: AccountStore, initialEmail: String, onSuccess: @escaping () -> Void) {
        self.accountStore = accountStore
        self.onSuccess = onSuccess
        _email = State(initialValue: initialEmail.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isEmailValid: Bool { SanteValidation.isValidEmail(email) }
    private var codeDigits: String { code.filter(\.isNumber) }
    private var isCodeValid: Bool { SanteValidation.isValidCode(code) }
    private var passwordCheck: SanteValidation.PasswordCheck { SanteValidation.checkPassword(password) }
    private var hasMinLength: Bool { passwordCheck.hasMinLength }
    private var hasUppercase: Bool { passwordCheck.hasUppercase }
    private var hasSpecialChar: Bool { passwordCheck.hasSpecialChar }
    private var isPasswordValid: Bool { passwordCheck.isValid }
    private var isBusy: Bool { accountStore.isConnecting }

    var body: some View {
        ZStack {
            SanteBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 25) {
                    HStack {
                        SanteIconButton(systemName: step == .code ? "chevron.left" : "xmark",
                                        label: step == .code ? "Voltar" : "Fechar") {
                            if step == .code {
                                withAnimation { step = .email }
                                errorMessage = nil
                            } else {
                                dismiss()
                            }
                        }
                        Spacer()
                        SanteLogo()
                    }
                    .padding(.top, 14)

                    switch step {
                    case .email: emailStep
                    case .code: codeStep
                    case .done: doneStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.2), value: step)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(step == .done)
        .onAppear { focusedField = isEmailValid ? nil : .email }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 25) {
            header(
                title: "Recuperar senha",
                message: "Informe o e-mail da sua conta. Vamos enviar um código para você criar uma nova senha."
            )

            VStack(alignment: .leading, spacing: 19) {
                fieldTitle("E-mail")
                HStack(spacing: 11) {
                    Image(systemName: "envelope").foregroundStyle(Sante.inkSoft)
                    TextField("seuemail@exemplo.com", text: $email)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.send)
                        .onSubmit(sendCode)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                }
                .santeField(isFocused: focusedField == .email)

                errorView

                Button(action: sendCode) {
                    busyLabel("Enviar código", icon: "paperplane.fill")
                }
                .buttonStyle(SantePrimaryButtonStyle(enabled: isEmailValid && !isBusy))
                .disabled(!isEmailValid || isBusy)
            }
            .santeCard(padding: 21)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 25) {
            header(
                title: "Confira seu e-mail",
                message: "Se existir uma conta com \(email.trimmingCharacters(in: .whitespacesAndNewlines)), você vai receber um código em instantes. Olhe também a caixa de spam."
            )

            VStack(alignment: .leading, spacing: 19) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldTitle("Código")
                    HStack(spacing: 11) {
                        Image(systemName: "number").foregroundStyle(Sante.inkSoft)
                        TextField("000000", text: $code)
                            .focused($focusedField, equals: .code)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .tracking(4)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            #endif
                            .onChange(of: code) { _, newValue in
                                let digits = String(newValue.filter(\.isNumber).prefix(10))
                                if digits != newValue { code = digits }
                            }
                    }
                    .santeField(isFocused: focusedField == .code)
                }

                VStack(alignment: .leading, spacing: 8) {
                    fieldTitle("Nova senha")
                    HStack(spacing: 11) {
                        Image(systemName: "lock").foregroundStyle(Sante.inkSoft)
                        Group {
                            if isPasswordVisible {
                                TextField("Crie uma nova senha", text: $password)
                            } else {
                                SecureField("Crie uma nova senha", text: $password)
                            }
                        }
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit(confirm)
                        #if os(iOS)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        Button { isPasswordVisible.toggle() } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(Sante.inkSoft)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPasswordVisible ? "Ocultar senha" : "Mostrar senha")
                    }
                    .santeField(isFocused: focusedField == .password)

                    HStack(spacing: 6) {
                        PasswordRequirementChip(text: "6+ caracteres", met: hasMinLength)
                        PasswordRequirementChip(text: "1 maiúscula", met: hasUppercase)
                        PasswordRequirementChip(text: "1 símbolo", met: hasSpecialChar)
                    }
                    .padding(.top, 2)
                }

                errorView

                Button(action: confirm) {
                    busyLabel("Salvar nova senha", icon: "checkmark")
                }
                .buttonStyle(SantePrimaryButtonStyle(enabled: isCodeValid && isPasswordValid && !isBusy))
                .disabled(!isCodeValid || !isPasswordValid || isBusy)

                resendButton
            }
            .santeCard(padding: 21)
        }
    }

    private var resendButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(resendAvailableAt.timeIntervalSince(context.date).rounded(.up))
            Button(action: sendCode) {
                Text(remaining > 0 ? "Reenviar código em \(remaining)s" : "Não recebeu? Reenviar código")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(remaining > 0 ? Sante.inkSoft : Sante.primary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(remaining > 0 || isBusy)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Sante.success)
                .padding(.top, 30)
            Text("Senha alterada!")
                .font(Sante.display(28))
                .foregroundStyle(Sante.ink)
            Text("Sua nova senha já está valendo e você entrou na sua conta.")
                .font(Sante.body)
                .foregroundStyle(Sante.inkSoft)
                .multilineTextAlignment(.center)
            Button(action: onSuccess) {
                Text("Continuar")
            }
            .buttonStyle(SantePrimaryButtonStyle())
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private func sendCode() {
        guard isEmailValid, !isBusy, Date() >= resendAvailableAt else { return }
        focusedField = nil
        errorMessage = nil
        Task {
            if let error = await accountStore.sendPasswordReset(email: email) {
                errorMessage = error
            } else {
                resendAvailableAt = Date().addingTimeInterval(resendInterval)
                withAnimation { step = .code }
                focusedField = .code
            }
        }
    }

    private func confirm() {
        guard isCodeValid, isPasswordValid, !isBusy else { return }
        focusedField = nil
        errorMessage = nil
        Task {
            if let error = await accountStore.confirmPasswordReset(email: email, code: codeDigits, newPassword: password) {
                errorMessage = error
            } else {
                withAnimation { step = .done }
            }
        }
    }

    private func header(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(Sante.display(30))
                .tracking(-0.5)
                .foregroundStyle(Sante.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Sante.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Sante.ink)
    }

    @ViewBuilder
    private var errorView: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Sante.coral)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }

    private func busyLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 9) {
            if isBusy {
                ProgressView().tint(.white)
            } else {
                Text(title)
                Image(systemName: icon)
            }
        }
    }
}

private extension View {
    func loginInput(isFocused: Bool) -> some View {
        santeField(isFocused: isFocused)
    }
}

@MainActor
private final class TiltMotion: ObservableObject {
    @Published var x: CGFloat = 0
    @Published var y: CGFloat = 0

    #if os(iOS)
    private let manager = CMMotionManager()
    #endif

    func start() {
        #if os(iOS)
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let attitude = data?.attitude else { return }
            MainActor.assumeIsolated {
                self?.x = CGFloat(max(-1, min(1, attitude.roll / 0.6)))
                self?.y = CGFloat(max(-1, min(1, (attitude.pitch - 0.7) / 0.6)))
            }
        }
        #endif
    }

    func stop() {
        #if os(iOS)
        manager.stopDeviceMotionUpdates()
        #endif
    }
}

private struct LeafSpec {
    let x: CGFloat
    let y: CGFloat
    let angle: Double
    let size: CGFloat
    var tone: Int = 0

    var mirrored: LeafSpec { LeafSpec(x: 1 - x, y: y, angle: -angle, size: size, tone: tone) }
}

private struct BranchSpec {
    let points: [CGPoint]
    var mirrored: BranchSpec { BranchSpec(points: points.map { CGPoint(x: 1 - $0.x, y: $0.y) }) }
}

private enum LeafLayout {
    static let frontLeft: [LeafSpec] = [
        LeafSpec(x: 0.04, y: 0.085, angle: -35, size: 0.14),
        LeafSpec(x: 0.10, y: 0.078, angle: 200, size: 0.12, tone: 1),
        LeafSpec(x: 0.16, y: 0.068, angle: -8, size: 0.13),
        LeafSpec(x: 0.22, y: 0.078, angle: 165, size: 0.11, tone: 2),
        LeafSpec(x: 0.28, y: 0.100, angle: 40, size: 0.10, tone: 1),
        LeafSpec(x: 0.02, y: 0.400, angle: 70, size: 0.12),
        LeafSpec(x: 0.05, y: 0.460, angle: 110, size: 0.11, tone: 1),
        LeafSpec(x: 0.06, y: 0.515, angle: 150, size: 0.10, tone: 2),
        LeafSpec(x: 0.03, y: 0.950, angle: -95, size: 0.12, tone: 1),
        LeafSpec(x: 0.07, y: 0.935, angle: -55, size: 0.13),
        LeafSpec(x: 0.13, y: 0.915, angle: -18, size: 0.12, tone: 2),
        LeafSpec(x: 0.19, y: 0.905, angle: 28, size: 0.10)
    ]
    static let frontBranchesLeft: [BranchSpec] = [
        BranchSpec(points: [CGPoint(x: -0.04, y: 0.105), CGPoint(x: 0.04, y: 0.085), CGPoint(x: 0.16, y: 0.068), CGPoint(x: 0.28, y: 0.100)]),
        BranchSpec(points: [CGPoint(x: -0.04, y: 0.360), CGPoint(x: 0.02, y: 0.400), CGPoint(x: 0.05, y: 0.460), CGPoint(x: 0.06, y: 0.515)]),
        BranchSpec(points: [CGPoint(x: -0.04, y: 0.985), CGPoint(x: 0.03, y: 0.950), CGPoint(x: 0.13, y: 0.915), CGPoint(x: 0.19, y: 0.905)])
    ]

    static let middleLeft: [LeafSpec] = [
        LeafSpec(x: 0.01, y: 0.200, angle: 75, size: 0.11, tone: 2),
        LeafSpec(x: 0.30, y: 0.030, angle: 25, size: 0.09, tone: 2),
        LeafSpec(x: 0.01, y: 0.640, angle: 95, size: 0.10, tone: 2),
        LeafSpec(x: 0.15, y: 0.820, angle: -40, size: 0.09, tone: 2)
    ]

    static let back: [LeafSpec] = [
        LeafSpec(x: 0.42, y: 0.42, angle: -22, size: 0.20, tone: 3),
        LeafSpec(x: 0.58, y: 0.44, angle: 18, size: 0.16, tone: 3),
        LeafSpec(x: 0.50, y: 0.33, angle: 4, size: 0.13, tone: 3)
    ]

    static let front = frontLeft + frontLeft.map(\.mirrored)
    static let frontBranches = frontBranchesLeft + frontBranchesLeft.map(\.mirrored)
    static let middle = middleLeft + middleLeft.map(\.mirrored)
}

private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let base = CGPoint(x: rect.midX, y: rect.maxY)
        let tip = CGPoint(x: rect.midX, y: rect.minY)
        var path = Path()
        path.move(to: base)
        path.addCurve(to: tip,
                      control1: CGPoint(x: rect.minX - w * 0.18, y: rect.maxY - h * 0.38),
                      control2: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.10))
        path.addCurve(to: base,
                      control1: CGPoint(x: rect.maxX - w * 0.12, y: rect.minY + h * 0.10),
                      control2: CGPoint(x: rect.maxX + w * 0.18, y: rect.maxY - h * 0.38))
        path.closeSubpath()
        return path
    }
}

private struct LeafVeins: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY + h * 0.06),
                          control: CGPoint(x: rect.midX + w * 0.04, y: rect.midY))
        for step in 1...4 {
            let y = rect.maxY - h * (0.18 * CGFloat(step))
            path.move(to: CGPoint(x: rect.midX, y: y))
            path.addQuadCurve(to: CGPoint(x: rect.midX - w * 0.32, y: y - h * 0.10),
                              control: CGPoint(x: rect.midX - w * 0.14, y: y - h * 0.02))
            path.move(to: CGPoint(x: rect.midX, y: y - h * 0.04))
            path.addQuadCurve(to: CGPoint(x: rect.midX + w * 0.32, y: y - h * 0.14),
                              control: CGPoint(x: rect.midX + w * 0.14, y: y - h * 0.06))
        }
        return path
    }
}

private struct LeafView: View {
    let width: CGFloat
    let tone: Int

    private static let tones: [[Color]] = [
        [Color(red: 0.55, green: 0.76, blue: 0.38), Color(red: 0.22, green: 0.50, blue: 0.22)],
        [Color(red: 0.66, green: 0.82, blue: 0.47), Color(red: 0.31, green: 0.58, blue: 0.27)],
        [Color(red: 0.46, green: 0.68, blue: 0.36), Color(red: 0.15, green: 0.40, blue: 0.22)],
        [Color(red: 0.86, green: 0.93, blue: 0.86), Color(red: 0.74, green: 0.86, blue: 0.76)]
    ]

    var body: some View {
        let colors = Self.tones[min(tone, Self.tones.count - 1)]
        let height = width * 1.8
        VStack(spacing: 0) {
            LeafShape()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    LeafVeins()
                        .stroke(.white.opacity(tone == 3 ? 0.5 : 0.32), lineWidth: max(0.6, width * 0.014))
                        .clipShape(LeafShape())
                )
                .frame(width: width, height: height)
            Capsule()
                .fill(colors[1].opacity(0.8))
                .frame(width: max(1, width * 0.04), height: height * 0.14)
        }
    }

    static func totalHeight(for width: CGFloat) -> CGFloat { width * 1.8 * 1.14 }
}

private struct BranchShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        let pts = points.map { CGPoint(x: $0.x * rect.width, y: $0.y * rect.height) }
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for index in 1..<pts.count {
            let previous = pts[index - 1], current = pts[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            if index == pts.count - 1 { path.addLine(to: current) }
        }
        return path
    }
}

private struct LeafParallaxFrame: View {
    let page: Int
    @StateObject private var motion = TiltMotion()
    @State private var sway = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RadialGradient(colors: [Sante.mintDeep.opacity(0.55), .clear],
                               center: UnitPoint(x: 0.5, y: 0.12), startRadius: 0, endRadius: size.width * 0.7)

                layer(LeafLayout.back, branches: [], size: size, depth: 0.25)
                    .opacity(0.9)
                    .blur(radius: 1.2)

                layer(LeafLayout.middle, branches: [], size: size, depth: 0.55)
                    .opacity(0.75)
                    .blur(radius: 0.6)

                layer(LeafLayout.front, branches: LeafLayout.frontBranches, size: size, depth: 1.0)
                    .shadow(color: Color(red: 0.1, green: 0.3, blue: 0.15).opacity(0.18), radius: 6, y: 4)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            motion.start()
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { sway = true }
        }
        .onDisappear { motion.stop() }
    }

    private func layer(_ leaves: [LeafSpec], branches: [BranchSpec], size: CGSize, depth: CGFloat) -> some View {
        let offsetX = (motion.x * 16 - CGFloat(page) * 10) * depth
        let offsetY = motion.y * 12 * depth
        return ZStack {
            ForEach(Array(branches.enumerated()), id: \.offset) { _, branch in
                BranchShape(points: branch.points)
                    .stroke(Color(red: 0.30, green: 0.45, blue: 0.25).opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            ForEach(Array(leaves.enumerated()), id: \.offset) { index, leaf in
                let width = leaf.size * size.width
                let height = LeafView.totalHeight(for: width)
                let swayAngle = reduceMotion ? 0 : (sway ? 2.5 : -2.5) * (index.isMultiple(of: 2) ? 1 : -1) * Double(depth)
                LeafView(width: width, tone: leaf.tone)
                    .rotationEffect(.degrees(leaf.angle + swayAngle), anchor: .bottom)
                    .position(x: leaf.x * size.width, y: leaf.y * size.height - height / 2)
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(x: offsetX, y: offsetY)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: page)
        .animation(.easeOut(duration: 0.25), value: motion.x)
        .animation(.easeOut(duration: 0.25), value: motion.y)
    }
}

#Preview {
    WelcomeView(previewOnboarding: true)
}
