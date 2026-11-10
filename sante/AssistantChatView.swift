import SwiftUI
import Supabase

private struct AssistantMessage: Identifiable {
    enum Role: String, Encodable { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

private struct AssistantRequest: Encodable {
    let messages: [AssistantRequestMessage]
}

private struct AssistantRequestMessage: Encodable {
    let role: String
    let content: String
}

private struct AssistantResponse: Decodable {
    let reply: String
}

private struct OllamaRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let think: Bool
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaResponse: Decodable {
    let message: OllamaMessage
}

struct AssistantChatView: View {
    @Environment(\.dismiss) private var dismiss
    let onAppointmentTap: (String?) -> Void
    var initialMessage: String? = nil
    @State private var didSendInitialMessage = false
    @State private var messages = [AssistantMessage(
        role: .assistant,
        text: "Oi! Me conta: o que você está sentindo?"
    )]
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showAppointmentButton = false
    @State private var reportForEmail: String?
    @State private var showCloseConfirmation = false
    @State private var emergency: EmergencyAlert?

    private var isMidConversation: Bool {
        messages.contains { $0.role == .user } && !showAppointmentButton
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !showAppointmentButton
    }
    private var privacyNotice: String {
        #if DEBUG && targetEnvironment(simulator)
        "No simulador, suas mensagens são processadas localmente pelo Ollama neste computador. O resumo só segue para o médico se você revisar e enviar o e-mail; ele não é salvo no perfil."
        #else
        "Suas mensagens são processadas por um serviço de IA (Groq) apenas para gerar as respostas, sem serem guardadas por ele nem usadas para treinar IA. O resumo só segue para o médico se você revisar e enviar o e-mail; ele não é salvo no perfil."
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Sante.primary)
                    Text("Triagem Sante")
                        .font(Sante.title(15))
                        .foregroundStyle(Sante.ink)
                    Spacer()
                    Text("Anamnese inicial")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Sante.inkSoft)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(.white.opacity(0.8))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                            if isSending {
                                HStack {
                                    ProgressView().tint(Sante.primary)
                                    Text("Pensando…")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Sante.inkSoft)
                                    Spacer()
                                }
                                .padding(.horizontal, 18)
                                .id("sending")
                            }
                        }
                        .padding(.vertical, 18)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                    .onChange(of: isSending) { _, sending in
                        if sending { withAnimation { proxy.scrollTo("sending", anchor: .bottom) } }
                    }
                }

                if let emergency {
                    emergencyCard(emergency)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if showAppointmentButton {
                    Button {
                        onAppointmentTap(reportForEmail)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(.white.opacity(0.18), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Agende sua consulta")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Escolha a especialidade, data e horário")
                                    .font(.system(size: 12))
                                    .opacity(0.9)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Sante.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }

                if let errorMessage {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Sante.coral)
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Sante.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Tentar de novo", action: requestReply)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Sante.primary)
                            .buttonStyle(.plain)
                            .disabled(isSending)
                    }
                    .padding(12)
                    .background(Sante.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                HStack(alignment: .bottom, spacing: 10) {
                        TextField(showAppointmentButton ? "Triagem concluída" : "O que você está sentindo?", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .font(Sante.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Sante.stroke))
                        .disabled(isSending || showAppointmentButton)

                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(canSend ? Sante.primary : Sante.inkSoft.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("Enviar mensagem")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Text(privacyNotice)
                    .font(.system(size: 10))
                    .foregroundStyle(Sante.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 7)

                HStack(spacing: 4) {
                    Text("A IA pode errar. Não substitui um profissional de saúde. Em uma emergência,")
                        .foregroundStyle(Sante.inkSoft)
                    Link("ligue 192.", destination: URL(string: "tel:192")!)
                        .fontWeight(.semibold)
                        .foregroundStyle(Sante.coral)
                }
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(SanteBackground())
            .navigationTitle("Sante IA")
            .onAppear {
                guard let initialMessage, !didSendInitialMessage else { return }
                didSendInitialMessage = true
                draft = initialMessage
                send()
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Fechar") {
                        if isMidConversation { showCloseConfirmation = true } else { dismiss() }
                    }
                    .foregroundStyle(Sante.primary)
                }
            }
            .interactiveDismissDisabled(isMidConversation)
            .confirmationDialog("Encerrar a triagem?", isPresented: $showCloseConfirmation, titleVisibility: .visible) {
                Button("Encerrar", role: .destructive) { dismiss() }
                Button("Continuar conversa", role: .cancel) { }
            } message: {
                Text("A conversa não fica salva. Se fechar agora, vai precisar começar de novo.")
            }
        }
    }

    private func emergencyCard(_ alert: EmergencyAlert) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Isso pode ser uma emergência")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)

            Text(alert.message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Link(destination: URL(string: "tel:192")!) {
                    Label("Ligar 192", systemImage: "phone.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Sante.coral)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if alert.includesCVV {
                    Link(destination: URL(string: "tel:188")!) {
                        Label("CVV 188", systemImage: "heart.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .background(Sante.coral, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func messageBubble(_ message: AssistantMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }
            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(message.role == .user ? .white : Sante.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(message.role == .user ? Sante.primary : .white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
            if message.role == .assistant { Spacer(minLength: 44) }
        }
        .padding(.horizontal, 16)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        messages.append(AssistantMessage(role: .user, text: text))
        if let alert = EmergencyAlert.check(text) {
            withAnimation { emergency = alert }
            messages.append(AssistantMessage(role: .assistant, text: alert.reply))
            return
        }
        requestReply()
    }

    private func requestReply() {
        guard !isSending, messages.last?.role == .user else { return }
        errorMessage = nil
        isSending = true

        Task {
            defer { isSending = false }
            do {
                let history = messages.suffix(12).map {
                    AssistantRequestMessage(role: $0.role.rawValue, content: String($0.text.prefix(1500)))
                }
                #if DEBUG && targetEnvironment(simulator)
                let reply = try await askLocalOllama(history: history)
                messages.append(AssistantMessage(role: .assistant, text: reply))
                updateCompletionState(from: reply)
                #else
                let response: AssistantResponse = try await SupabaseBackend.client.functions.invoke(
                    "sante-assistant",
                    options: FunctionInvokeOptions(body: AssistantRequest(messages: history), timeoutInterval: 45)
                )
                messages.append(AssistantMessage(role: .assistant, text: response.reply))
                updateCompletionState(from: response.reply)
                #endif
            } catch {
                #if DEBUG && targetEnvironment(simulator)
                errorMessage = error.localizedDescription
                #else
                errorMessage = "Não foi possível responder agora. Confira sua conexão e tente novamente."
                #endif
            }
        }
    }

    private func updateCompletionState(from text: String) {
        let triageReply = TriageReply(text: text)
        guard triageReply.isComplete else { return }
        showAppointmentButton = true
        reportForEmail = triageReply.report
    }

    #if DEBUG && targetEnvironment(simulator)
    private func askLocalOllama(history: [AssistantRequestMessage]) async throws -> String {
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            throw OllamaConnectionError.unavailable
        }

        let safetyInstructions = """
        Você é a IA de triagem do Sante. Converse em português brasileiro como uma pessoa atenciosa: com gentileza, simplicidade e naturalidade, sem soar formal ou robótica. Seu trabalho é entender o que a pessoa está sentindo e preparar um resumo para a consulta. Comece com uma pergunta acolhedora e direta sobre o que a pessoa está sentindo. Faça uma pergunta curta por mensagem, usando palavras do dia a dia. Demonstre que ouviu a resposta com uma frase breve e natural quando isso ajudar, sem repetir sempre as mesmas expressões. Pergunte somente sobre os sintomas e apenas o que ainda não foi informado: por exemplo, quando começou, onde sente e como está agora. Não junte várias perguntas numa frase, não use termos médicos sem explicar, não investigue histórico ou medicamentos e não ofereça informação geral de saúde. Quando já houver informações suficientes, pare de perguntar e faça um resumo curto, simples e fiel ao que a pessoa contou, com o título "Resumo para a consulta". Não invente informações nem diagnóstico. Diga que o resumo é para mostrar ao médico e não afirme que foi enviado. Depois do resumo, escreva exatamente "Agende sua consulta no aplicativo Sante." Se a pessoa descrever sinais de emergência ou risco imediato — por exemplo dor ou aperto no peito (principalmente se for para o braço, costas ou queixo), falta de ar, desmaio, rosto ou boca torta, fraqueza ou dormência de um lado do corpo, fala enrolada, convulsão, sangramento intenso, reação alérgica com inchaço na garganta, ou pensamentos de se machucar — NÃO faça mais perguntas: diga com carinho e clareza para ligar agora para o SAMU no 192 ou ir ao pronto-socorro mais próximo. Se a pessoa falar em se machucar ou tirar a própria vida, diga também que ela pode ligar para o CVV no 188, a qualquer hora.
        """
        var localMessages = [OllamaMessage(role: "system", content: safetyInstructions)]
        localMessages.append(contentsOf: history.map { OllamaMessage(role: $0.role, content: $0.content) })

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaRequest(
            model: "qwen3.5:4b",
            messages: localMessages,
            stream: false,
            think: false
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OllamaConnectionError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw OllamaConnectionError.modelMissing }
            throw OllamaConnectionError.unavailable
        }
        let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
        let answer = result.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw OllamaConnectionError.emptyReply }
        return answer
    }
    #endif
}

#if DEBUG && targetEnvironment(simulator)
private enum OllamaConnectionError: LocalizedError {
    case unavailable
    case modelMissing
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Não consegui acessar o Ollama neste Mac. Abra o Ollama e tente novamente."
        case .modelMissing:
            return "O modelo de IA ainda não está instalado. No Ollama, baixe o modelo qwen3.5:4b e tente novamente."
        case .emptyReply:
            return "O Ollama não retornou uma resposta. Tente novamente."
        }
    }
}
#endif

struct EmergencyAlert: Equatable {
    let message: String
    let includesCVV: Bool

    let reply: String

    private static let medicalSigns = [
        "dor no peito", "dor forte no peito", "aperto no peito", "peito apertado", "pressao no peito",
        "falta de ar", "sem ar", "nao consigo respirar", "dificuldade para respirar", "dificuldade de respirar",
        "desmaiei", "desmaiou", "desmaio", "apaguei",
        "rosto torto", "boca torta", "rosto caido", "nao consigo mexer", "nao consigo falar", "fala enrolada",
        "dormencia de um lado", "formigamento de um lado", "um lado do corpo",
        "convulsao", "convulsionando",
        "sangramento forte", "sangrando muito", "muito sangue", "vomitando sangue", "vomito com sangue", "tossindo sangue",
        "garganta fechando", "inchaco na garganta", "nao consigo engolir",
        "overdose", "envenenamento", "envenenei"
    ]

    private static let selfHarmSigns = [
        "me matar", "suicid", "tirar minha vida", "tirar a minha vida", "acabar com a minha vida",
        "acabar com minha vida", "me machucar", "nao quero mais viver", "nao quero viver", "quero morrer",
        "pensando em morrer", "me cortar", "me ferir"
    ]

    private static let medicalCombos: [[String]] = [
        ["peito", "dor"], ["peito", "aperto"], ["peito", "apertado"], ["peito", "pressao"], ["peito", "queima"],
        ["rosto", "torto"], ["rosto", "caido"], ["boca", "torta"], ["boca", "caida"],
        ["garganta", "fechando"], ["garganta", "inchad"], ["lingua", "inchad"],
        ["sangue", "muito"], ["sangue", "vomit"], ["sangue", "toss"], ["sangrando", "muito"],
        ["respirar", "nao consigo"], ["respirar", "dificuldade"], ["ar", "falta"]
    ]

    static func check(_ text: String) -> EmergencyAlert? {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let words = Set(normalized.split(whereSeparator: { !$0.isLetter }).map(String.init))

        func has(_ piece: String) -> Bool {
            piece.contains(" ") ? normalized.contains(piece) : words.contains { $0.hasPrefix(piece) && (piece.count > 2 || $0 == piece) }
        }
        if selfHarmSigns.contains(where: { normalized.contains($0) }) {
            return EmergencyAlert(
                message: "Se estiver em risco agora, ligue para o SAMU (192). Para conversar com alguém a qualquer hora, ligue para o CVV (188). É gratuito.",
                includesCVV: true,
                reply: "Sinto muito que você esteja passando por isso. Obrigada por me contar. Você não precisa enfrentar isso sozinha ou sozinho. Se estiver em perigo agora, ligue para o SAMU no 192. Se quiser conversar com alguém agora, o CVV atende a qualquer hora pelo 188, de graça. Se puder, chame também alguém de confiança para ficar com você."
            )
        }
        if medicalSigns.contains(where: { normalized.contains($0) })
            || medicalCombos.contains(where: { $0.allSatisfy(has) }) {
            return EmergencyAlert(
                message: "Pelo que você contou, o mais seguro é procurar ajuda agora. Ligue para o SAMU (192) ou vá ao pronto-socorro mais próximo. Não espere a triagem terminar.",
                includesCVV: false,
                reply: "O que você contou pode ser sinal de algo sério, e o mais seguro é ter atendimento agora. Por favor, ligue para o SAMU no 192 ou vá ao pronto-socorro mais próximo. Se tiver alguém perto, peça ajuda. Quando estiver bem, a gente continua por aqui."
            )
        }
        return nil
    }
}
