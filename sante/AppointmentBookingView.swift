import SwiftUI
#if os(iOS)
import MessageUI
#endif

struct AppointmentBookingView: View {
    @Environment(\.dismiss) private var dismiss
    let report: String?
    var patient: SanteUser? = nil

    var initialSpecialty: String? = nil

    @State private var specialty = "Clínica geral"
    @State private var appointmentDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var appointmentTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var doctorEmail = ""
    @State private var showMailComposer = false
    @State private var sendResult: String?
    @State private var closeAfterAlert = false

    private let specialties = ["Clínica geral", "Cardiologia", "Dermatologia", "Ginecologia", "Pediatria", "Psicologia"]

    private var isEmailValid: Bool {
        let value = doctorEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains("@") && value.split(separator: "@").last?.contains(".") == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Escolha a especialidade e o horário que prefere. O médico recebe o pedido por e-mail e responde para confirmar.")
                        .font(.system(size: 14))
                        .foregroundStyle(Sante.inkSoft)
                }

                Section("Consulta") {
                    Picker("Especialidade", selection: $specialty) {
                        ForEach(specialties, id: \.self) { Text($0).tag($0) }
                    }
                    DatePicker(
                        "Data preferida",
                        selection: $appointmentDate,
                        in: (Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())...,
                        displayedComponents: .date
                    )
                    DatePicker("Horário preferido", selection: $appointmentTime, displayedComponents: .hourAndMinute)
                }

                if let patient {
                    Section("Paciente") {
                        LabeledContent("Nome", value: patient.fullName)
                        if !patient.phone.isEmpty {
                            LabeledContent("Telefone", value: "\(patient.countryCode) \(patient.phone)")
                        }
                        LabeledContent("E-mail", value: patient.email)
                    }
                    .font(.system(size: 15))
                }

                Section("E-mail do médico") {
                    TextField("medico@exemplo.com", text: $doctorEmail)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                }

                if let report {
                    Section("Resumo da triagem") {
                        Text(report)
                            .font(.system(size: 14))
                            .foregroundStyle(Sante.ink)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Label("Isto é um pedido, não uma reserva. A consulta só está marcada quando o médico responder confirmando.", systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Sante.inkSoft)
                }

                Section {
                    #if os(iOS)
                    if MFMailComposeViewController.canSendMail() {
                        Button {
                            showMailComposer = true
                        } label: {
                            Text("Revisar e enviar pedido")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .disabled(!isEmailValid)
                        .listRowBackground(isEmailValid ? Sante.primary : Sante.cream)
                        .foregroundStyle(isEmailValid ? .white : Sante.inkSoft)
                    } else {
                        if let mailtoURL {
                            Link(destination: mailtoURL) {
                                Text("Abrir no app de e-mail")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .disabled(!isEmailValid)
                            .listRowBackground(isEmailValid ? Sante.primary : Sante.cream)
                            .foregroundStyle(isEmailValid ? .white : Sante.inkSoft)
                        }
                        ShareLink(item: emailDraft) {
                            Label("Copiar ou compartilhar o pedido", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .disabled(!isEmailValid)
                    }
                    #else
                    ShareLink(item: emailDraft) {
                        Label("Compartilhar pedido por e-mail", systemImage: "envelope")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(!isEmailValid)
                    #endif
                }
            }
            .scrollContentBackground(.hidden)
            .background(SanteBackground())
            .navigationTitle("Solicitar consulta")
            .onAppear {
                if let initialSpecialty, specialties.contains(initialSpecialty) { specialty = initialSpecialty }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(Sante.primary)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showMailComposer) {
                AppointmentMailComposer(
                    recipient: doctorEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                    subject: "Solicitação de consulta pelo Sante",
                    body: emailBody,
                    onFinish: { result in
                        switch result {
                        case .sent:
                            closeAfterAlert = true
                            sendResult = "Pedido enviado. Quando o médico responder confirmando, a consulta está marcada."
                        case .saved: sendResult = "Rascunho salvo no aplicativo Mail."
                        case .cancelled: sendResult = nil
                        case .failed: sendResult = "Não foi possível enviar o pedido. Tente novamente."
                        @unknown default: sendResult = nil
                        }
                    }
                )
            }
            #endif
            .alert("Pedido de consulta", isPresented: Binding(
                get: { sendResult != nil },
                set: { if !$0 { sendResult = nil } }
            )) {
                Button("OK", role: .cancel) {
                    sendResult = nil
                    if closeAfterAlert { dismiss() }
                }
            } message: {
                Text(sendResult ?? "")
            }
        }
    }

    private var emailBody: String {
        var lines = [
            "Olá,",
            "",
            "Gostaria de solicitar uma consulta pelo Sante."
        ]
        if let patient {
            lines += ["", "Paciente: \(patient.fullName)"]
            if !patient.phone.isEmpty { lines.append("Telefone: \(patient.countryCode) \(patient.phone)") }
            if let birth = patient.dateOfBirth {
                lines.append("Data de nascimento: \(birth.formatted(date: .long, time: .omitted))")
            }
            lines.append("")
        }
        lines += [
            "Especialidade: \(specialty)",
            "Data preferida: \(appointmentDate.formatted(date: .long, time: .omitted))",
            "Horário preferido: \(appointmentTime.formatted(date: .omitted, time: .shortened))"
        ]
        if let report {
            lines += ["", "Resumo da triagem:", report, "", "O resumo foi elaborado por IA e deve ser revisado pelo profissional de saúde."]
        }
        lines += ["", "Por favor, confirme a disponibilidade respondendo a este e-mail."]
        return lines.joined(separator: "\n")
    }

    private var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = doctorEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Solicitação de consulta pelo Sante"),
            URLQueryItem(name: "body", value: emailBody)
        ]
        return components.url
    }

    private var emailDraft: String {
        "Para: \(doctorEmail)\nAssunto: Solicitação de consulta pelo Sante\n\n\(emailBody)"
    }
}

#if os(iOS)
private struct AppointmentMailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.setToRecipients([recipient])
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)
        composer.mailComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) { }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { self.onFinish(result) }
        }
    }
}
#endif
