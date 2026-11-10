import SwiftUI

struct SignupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var accountStore: AccountStore
    var onAccountCreated: (() -> Void)? = nil

    var onSignIn: (() -> Void)? = nil

    @State private var name = ""
    @State private var cpf = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var selectedCountryCode = "+55"
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var showAlert = false
    @State private var signupSucceeded = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var acceptedTerms = false
    @State private var showEmailConfirmation = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, cpf, phone, email, password
    }

    let countryCodes = ["+55", "+351", "+1", "+44", "+34", "+54", "+598"]

    private var cpfDigits: String { SanteValidation.cpfDigits(cpf) }

    private var isCpfValid: Bool { SanteValidation.isValidCPF(cpf) }

    private var passwordCheck: SanteValidation.PasswordCheck { SanteValidation.checkPassword(password) }
    private var hasMinLength: Bool { passwordCheck.hasMinLength }
    private var hasUppercase: Bool { passwordCheck.hasUppercase }
    private var hasSpecialChar: Bool { passwordCheck.hasSpecialChar }
    private var isPasswordValid: Bool { passwordCheck.isValid }
    private var isEmailValid: Bool { SanteValidation.isValidEmail(email) }
    private var isPhoneValid: Bool { SanteValidation.isValidPhone(phone) }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && isCpfValid && isEmailValid && isPasswordValid && isPhoneValid && acceptedTerms
    }

    private var progress: Double {
        let checks = [!name.isEmpty, isCpfValid, isPhoneValid, isEmailValid, isPasswordValid, acceptedTerms]
        return Double(checks.filter { $0 }.count) / Double(checks.count)
    }

    var body: some View {
        ZStack {
            SanteBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        SanteIconButton(systemName: "chevron.left", label: "Voltar") { dismiss() }
                        Spacer()
                        SanteLogo()
                    }
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Crie sua conta")
                            .font(Sante.display(30))
                            .foregroundStyle(Sante.ink)
                        Text("Leva menos de um minuto. Seus dados ficam protegidos.")
                            .font(Sante.body)
                            .foregroundStyle(Sante.inkSoft)

                        ProgressView(value: progress)
                            .tint(Sante.primary)
                            .padding(.top, 8)
                            .animation(.easeOut, value: progress)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        field("Nome completo") {
                            HStack(spacing: 11) {
                                fieldIcon("person")
                                TextField("Como devemos te chamar?", text: $name)
                                    .focused($focusedField, equals: .name)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .cpf }
                                    #if os(iOS)
                                    .textContentType(.name)
                                    #endif
                            }
                            .santeField(isFocused: focusedField == .name)
                        }

                        field("CPF") {
                            HStack(spacing: 11) {
                                fieldIcon("person.text.rectangle")
                                TextField("000.000.000-00", text: $cpf)
                                    .focused($focusedField, equals: .cpf)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                                    .onChange(of: cpf) { _, newValue in
                                        let formatted = formatCPF(newValue)
                                        if formatted != newValue { cpf = formatted }
                                    }
                                if isCpfValid {
                                    validMark
                                }
                            }
                            .santeField(
                                isFocused: focusedField == .cpf,
                                isValid: cpfDigits.count == 11 ? isCpfValid : nil
                            )
                            if cpfDigits.count == 11 && !isCpfValid {
                                hint("CPF inválido. Confira os números.", color: Sante.coral)
                            }
                        }

                        field("Telefone") {
                            HStack(spacing: 8) {
                                Menu {
                                    ForEach(countryCodes, id: \.self) { code in
                                        Button(code) { selectedCountryCode = code }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(selectedCountryCode)
                                            .font(.system(size: 15, weight: .semibold))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(Sante.ink)
                                    .frame(width: 78, height: 52)
                                    .background(.white, in: RoundedRectangle(cornerRadius: Sante.radiusS, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Sante.radiusS, style: .continuous).stroke(Sante.stroke))
                                }

                                HStack(spacing: 11) {
                                    fieldIcon("phone")
                                    TextField("(11) 98888-7777", text: $phone)
                                        .focused($focusedField, equals: .phone)
                                        #if os(iOS)
                                        .keyboardType(.phonePad)
                                        #endif
                                        .onChange(of: phone) { _, newValue in
                                            let digits = newValue.filter(\.isNumber)
                                            if digits != newValue { phone = digits }
                                        }
                                }
                                .santeField(isFocused: focusedField == .phone)
                            }
                        }

                        field("E-mail") {
                            HStack(spacing: 11) {
                                fieldIcon("envelope")
                                TextField("seuemail@exemplo.com", text: $email)
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                                    #if os(iOS)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    #endif
                                if isEmailValid { validMark }
                            }
                            .santeField(isFocused: focusedField == .email)
                        }

                        field("Senha") {
                            HStack(spacing: 11) {
                                fieldIcon("lock")
                                Group {
                                    if isPasswordVisible {
                                        TextField("Crie uma senha", text: $password)
                                    } else {
                                        SecureField("Crie uma senha", text: $password)
                                    }
                                }
                                .focused($focusedField, equals: .password)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
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

                        Button {
                            acceptedTerms.toggle()
                        } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20))
                                    .foregroundStyle(acceptedTerms ? Sante.primary : Sante.inkSoft)
                                Text("Li e aceito os Termos de Uso e a Política de Privacidade, e autorizo o uso dos meus dados de saúde para organizar meu atendimento.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Sante.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(acceptedTerms ? .isSelected : [])
                        .padding(.top, 4)

                        Link(destination: SanteLegal.documentsURL) {
                            Label("Ler os Termos de Uso e a Política de Privacidade", systemImage: "doc.text")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Sante.primary)
                        }
                        .padding(.leading, 31)

                        Button(action: createAccount) {
                            if accountStore.isConnecting {
                                ProgressView().tint(.white)
                            } else {
                                HStack(spacing: 9) {
                                    Text("Criar conta")
                                    Image(systemName: "arrow.right")
                                }
                            }
                        }
                        .buttonStyle(SantePrimaryButtonStyle(enabled: isFormValid && !accountStore.isConnecting))
                        .disabled(!isFormValid || accountStore.isConnecting)
                        .padding(.top, 2)
                    }
                    .santeCard(padding: 20)

                    if let onSignIn {
                        HStack(spacing: 5) {
                            Spacer(minLength: 0)
                            Text("Já tem uma conta?")
                                .foregroundStyle(Sante.inkSoft)
                            Button("Entrar", action: onSignIn)
                                .fontWeight(.semibold)
                                .foregroundStyle(Sante.primary)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 14))
                        .padding(.bottom, 24)
                    }
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showEmailConfirmation) {
            EmailConfirmationView(
                accountStore: accountStore,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                codeAlreadySent: true
            ) {
                showEmailConfirmation = false
                dismiss()
                onAccountCreated?()
            }
            #if os(iOS)
            .presentationDetents([.large])
            #endif
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button(signupSucceeded ? "Começar" : "OK") {
                if signupSucceeded {
                    dismiss()
                    onAccountCreated?()
                }
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func createAccount() {
        focusedField = nil
        Task {
            let outcome = await accountStore.registerRemote(
                fullName: name, cpf: cpfDigits, email: email, countryCode: selectedCountryCode,
                phone: phone, password: password
            )
            switch outcome {
            case .signedIn:
                signupSucceeded = true
                let firstName = (name.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name).localizedCapitalized
                alertTitle = "Conta criada"
                alertMessage = "Boas-vindas ao Sante, \(firstName)."
                showAlert = true
            case .needsEmailConfirmation:
                showEmailConfirmation = true
            case .failed(let message):
                signupSucceeded = false
                alertTitle = "Não foi possível criar a conta"
                alertMessage = message
                showAlert = true
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Sante.ink)
            content()
        }
    }

    private func fieldIcon(_ name: String) -> some View {
        Image(systemName: name)
            .foregroundStyle(Sante.inkSoft)
            .frame(width: 20)
    }

    private var validMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Sante.success)
            .transition(.scale.combined(with: .opacity))
    }

    private func hint(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
    }

    private func formatCPF(_ value: String) -> String {
        let numbers = Array(value.filter(\.isNumber).prefix(11))
        var result = ""
        var index = 0
        for char in "###.###.###-##" where index < numbers.count {
            if char == "#" {
                result.append(numbers[index])
                index += 1
            } else {
                result.append(char)
            }
        }
        return result
    }
}

struct PasswordRequirementChip: View {
    let text: String
    let met: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: met ? "checkmark" : "circle")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(met ? Sante.success : Sante.inkSoft.opacity(0.8))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(met ? Sante.success.opacity(0.12) : Sante.cream, in: Capsule())
        .animation(.easeOut(duration: 0.2), value: met)
    }
}

#Preview {
    SignupView(accountStore: AccountStore())
}

struct EmailConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var accountStore: AccountStore
    let email: String

    let codeAlreadySent: Bool
    let onConfirmed: () -> Void

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var resendAvailableAt = Date.distantPast
    @FocusState private var codeFocused: Bool

    private var codeDigits: String { code.filter(\.isNumber) }
    private var isCodeValid: Bool { SanteValidation.isValidCode(code) }

    var body: some View {
        ZStack {
            SanteBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 25) {
                    HStack {
                        SanteIconButton(systemName: "xmark", label: "Fechar") { dismiss() }
                        Spacer()
                        SanteLogo()
                    }
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Confirme seu e-mail")
                            .font(Sante.display(30))
                            .foregroundStyle(Sante.ink)
                        Text("Enviamos um código para \(email). Digite abaixo para ativar sua conta. Se não encontrar, olhe a caixa de spam.")
                            .font(.system(size: 15))
                            .foregroundStyle(Sante.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        Text("Código")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Sante.ink)
                        TextField("000000", text: $code)
                            .focused($codeFocused)
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .tracking(5)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            #endif
                            .onChange(of: code) { _, newValue in
                                let digits = String(newValue.filter(\.isNumber).prefix(10))
                                if digits != newValue { code = digits }
                            }
                            .santeField(isFocused: codeFocused)

                        if let errorMessage { SanteErrorText(message: errorMessage) }

                        Button(action: confirm) {
                            if accountStore.isConnecting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Confirmar e entrar")
                            }
                        }
                        .buttonStyle(SantePrimaryButtonStyle(enabled: isCodeValid && !accountStore.isConnecting))
                        .disabled(!isCodeValid || accountStore.isConnecting)

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = Int(resendAvailableAt.timeIntervalSince(context.date).rounded(.up))
                            Button(action: resend) {
                                Text(remaining > 0 ? "Reenviar código em \(remaining)s" : "Não recebeu? Reenviar código")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(remaining > 0 ? Sante.inkSoft : Sante.primary)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(remaining > 0 || accountStore.isConnecting)
                        }
                    }
                    .santeCard(padding: 21)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.light)
        .onAppear {
            codeFocused = true
            if codeAlreadySent {
                resendAvailableAt = Date().addingTimeInterval(60)
            } else {
                resend()
            }
        }
    }

    private func confirm() {
        guard isCodeValid, !accountStore.isConnecting else { return }
        errorMessage = nil
        Task {
            if let error = await accountStore.confirmEmail(email: email, code: codeDigits) {
                errorMessage = error
            } else {
                onConfirmed()
            }
        }
    }

    private func resend() {
        errorMessage = nil
        resendAvailableAt = Date().addingTimeInterval(60)
        Task {
            if let error = await accountStore.resendConfirmationCode(email: email) {
                errorMessage = error
                resendAvailableAt = .distantPast
            }
        }
    }
}

enum SanteLegal {
    static let documentsURL = URL(string: "https://claude.ai/artifact/HdPo3jRBibuW4HGLoLTRyr")!
}
