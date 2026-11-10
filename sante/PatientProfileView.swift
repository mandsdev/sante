import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import ImageIO
#if os(iOS)
import UIKit
#endif

struct PatientProfileView: View {
    @ObservedObject var accountStore: AccountStore
    let focusDocuments: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var fullName: String
    @State private var countryCode: String
    @State private var phone: String
    @State private var dateOfBirth: Date?
    @State private var weight: String
    @State private var height: String
    @State private var bloodType: String
    @State private var allergies: String
    @State private var healthConditions: String
    @State private var medications: String
    @State private var emergencyContact: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isImportingDocuments = false
    @State private var previewURL: URL?
    @State private var alertMessage: String?
    @State private var hasDateOfBirth: Bool
    @State private var isSaving = false
    @State private var uploadsInProgress = 0
    @State private var attachmentPendingRemoval: PatientAttachment?
    @State private var showSignOutConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var isUploadingPhoto = false
    @State private var openingAttachmentID: UUID?
    @State private var savedDraft: ProfileDraft

    private struct ProfileDraft: Equatable {
        var fullName, phone, weight, height, bloodType, allergies, healthConditions, medications, emergencyContact: String
        var dateOfBirth: Date?
    }

    private var currentDraft: ProfileDraft {
        ProfileDraft(
            fullName: fullName, phone: phone, weight: weight, height: height, bloodType: bloodType,
            allergies: allergies, healthConditions: healthConditions, medications: medications,
            emergencyContact: emergencyContact, dateOfBirth: hasDateOfBirth ? dateOfBirth : nil
        )
    }

    private var hasUnsavedChanges: Bool { currentDraft != savedDraft }

    private enum KeyboardKind { case standard, phone, decimal }

    private let bloodTypes = ["Não informado", "A+", "A−", "B+", "B−", "AB+", "AB−", "O+", "O−"]

    init(accountStore: AccountStore, focusDocuments: Bool = false) {
        self.accountStore = accountStore
        self.focusDocuments = focusDocuments
        let user = accountStore.currentUser
        _fullName = State(initialValue: user?.fullName ?? "")
        _countryCode = State(initialValue: user?.countryCode ?? "+55")
        _phone = State(initialValue: user?.phone ?? "")
        _dateOfBirth = State(initialValue: user?.dateOfBirth)
        _weight = State(initialValue: user?.weightKg.map(Self.formatMeasure) ?? "")
        _height = State(initialValue: user?.heightCm.map(Self.formatMeasure) ?? "")
        _bloodType = State(initialValue: user?.bloodType ?? "Não informado")
        _allergies = State(initialValue: user?.allergies ?? "")
        _healthConditions = State(initialValue: user?.healthConditions ?? "")
        _medications = State(initialValue: user?.medications ?? "")
        _emergencyContact = State(initialValue: user?.emergencyContact ?? "")
        _hasDateOfBirth = State(initialValue: user?.dateOfBirth != nil)
        _savedDraft = State(initialValue: ProfileDraft(
            fullName: user?.fullName ?? "", phone: user?.phone ?? "",
            weight: user?.weightKg.map(Self.formatMeasure) ?? "",
            height: user?.heightCm.map(Self.formatMeasure) ?? "",
            bloodType: user?.bloodType ?? "Não informado",
            allergies: user?.allergies ?? "", healthConditions: user?.healthConditions ?? "",
            medications: user?.medications ?? "", emergencyContact: user?.emergencyContact ?? "",
            dateOfBirth: user?.dateOfBirth
        ))
    }

    var body: some View {
        ZStack {
            SanteBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        topBar
                        photoHeader

                        sectionHeader("Dados pessoais", subtitle: "Informações para manter seu perfil atualizado.")
                        personalInformation

                        sectionHeader("Sua saúde", subtitle: "Esses dados ajudam a contextualizar seu atendimento.")
                        healthInformation

                        sectionHeader("Documentos", subtitle: "Guarde exames, receitas e outros arquivos importantes.")
                            .id("documents")
                        documentsSection

                        Button(role: .destructive) {
                            showSignOutConfirmation = true
                        } label: {
                            Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)

                        Button(role: .destructive) {
                            showDeleteAccountConfirmation = true
                        } label: {
                            HStack(spacing: 8) {
                                if isDeletingAccount { ProgressView().tint(Sante.coral) }
                                Text(isDeletingAccount ? "Excluindo conta…" : "Excluir minha conta")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Sante.coral)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeletingAccount)

                        Link(destination: SanteLegal.documentsURL) {
                            Text("Termos de Uso e Política de Privacidade")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Sante.inkSoft)
                                .underline()
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.bottom, 28)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                .onAppear {
                    guard focusDocuments else { return }
                    DispatchQueue.main.async { proxy.scrollTo("documents", anchor: .top) }
                }
            }
        }
        .preferredColorScheme(.light)
        .fileImporter(
            isPresented: $isImportingDocuments,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true,
            onCompletion: handleDocumentImport
        )
        .quickLookPreview($previewURL)
        .alert("Não foi possível concluir", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "Tente novamente.")
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            isUploadingPhoto = true
            Task {
                defer {
                    isUploadingPhoto = false
                    selectedPhoto = nil
                }
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    alertMessage = "Não foi possível carregar essa foto. Escolha outra imagem."
                    return
                }
                do { try await accountStore.updateProfilePhotoRemote(data) }
                catch { alertMessage = "Não foi possível enviar a foto. Confira sua conexão e tente novamente." }
            }
        }
        .onChange(of: hasDateOfBirth) { _, isEnabled in
            if !isEnabled { dateOfBirth = nil }
        }
        .confirmationDialog(
            "Remover documento?",
            isPresented: Binding(
                get: { attachmentPendingRemoval != nil },
                set: { if !$0 { attachmentPendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: attachmentPendingRemoval
        ) { attachment in
            Button("Remover", role: .destructive) {
                Task {
                    do { try await accountStore.removeAttachmentRemote(attachment) }
                    catch { alertMessage = "Não foi possível remover o documento da conta. Tente novamente." }
                }
            }
            Button("Cancelar", role: .cancel) { }
        } message: { attachment in
            Text("\"\(attachment.name)\" será apagado da sua conta em todos os dispositivos.")
        }
        .interactiveDismissDisabled(hasUnsavedChanges || isDeletingAccount)
        .confirmationDialog("Salvar as alterações?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Salvar") { saveProfile() }
            Button("Descartar alterações", role: .destructive) { dismiss() }
            Button("Continuar editando", role: .cancel) { }
        } message: {
            Text("Você mudou dados do perfil e ainda não salvou.")
        }
        .confirmationDialog("Excluir sua conta?", isPresented: $showDeleteAccountConfirmation, titleVisibility: .visible) {
            Button("Excluir para sempre", role: .destructive) { deleteAccount() }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Seu perfil, dados de saúde, foto e documentos serão apagados. Isso não pode ser desfeito.")
        }
        .confirmationDialog("Sair da conta?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sair", role: .destructive) {
                Task {
                    await accountStore.signOutRemote()
                    dismiss()
                }
            }
            Button("Cancelar", role: .cancel) { }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Sante.ink)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.82), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voltar")

            Spacer()
            Text("Meu perfil")
                .font(Sante.title(18))
                .foregroundStyle(Sante.ink)
            Spacer()

            Group {
                if isSaving {
                    ProgressView()
                        .tint(Sante.primary)
                        .accessibilityLabel("Salvando")
                } else {
                    Button("Salvar", action: saveProfile)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(hasUnsavedChanges ? Sante.primary : Sante.inkSoft)
                        .buttonStyle(.plain)
                        .disabled(!hasUnsavedChanges)
                }
            }
            .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.bottom, 4)
    }

    private var photoHeader: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                avatar(size: 100)
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                    .shadow(color: Sante.ink.opacity(0.12), radius: 14, y: 6)
                    .overlay {
                        if isUploadingPhoto {
                            Circle().fill(.black.opacity(0.35))
                            ProgressView().tint(.white)
                        }
                    }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Sante.primary, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Editar foto de perfil")
            }

            VStack(spacing: 3) {
                Text(accountStore.currentUser?.fullName ?? fullName)
                    .font(Sante.title(19))
                    .foregroundStyle(Sante.ink)
                Text(accountStore.currentUser?.email ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(Sante.inkSoft)
            }

            if accountStore.currentUser?.profilePhotoFileName != nil {
                Button("Remover foto") {
                    Task {
                        do { try await accountStore.removeProfilePhotoRemote() }
                        catch { alertMessage = "Não foi possível remover a foto da conta. Tente novamente." }
                    }
                }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Sante.inkSoft)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var personalInformation: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeledField("Nome completo", text: $fullName, icon: "person")

            VStack(alignment: .leading, spacing: 7) {
                Text("E-mail da conta")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Sante.inkSoft)
                HStack(spacing: 10) {
                    Image(systemName: "envelope")
                        .foregroundStyle(Sante.inkSoft)
                    Text(accountStore.currentUser?.email ?? "")
                        .foregroundStyle(Sante.inkSoft)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Sante.inkSoft.opacity(0.7))
                }
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Sante.surface, in: RoundedRectangle(cornerRadius: Sante.radiusS, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Sante.radiusS).stroke(Sante.stroke))
            }

            labeledField("Telefone", text: $phone, icon: "phone", keyboard: .phone)

            VStack(alignment: .leading, spacing: 7) {
                Toggle("Adicionar data de nascimento", isOn: $hasDateOfBirth.animation())
                    .font(.system(size: 14, weight: .medium))
                    .tint(Sante.primary)
                    .foregroundStyle(Sante.ink)
                if hasDateOfBirth {
                    DatePicker(
                        "Data de nascimento",
                        selection: Binding(
                            get: { dateOfBirth ?? Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date() },
                            set: { dateOfBirth = $0 }
                        ),
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(Sante.primary)
                }
            }
            .font(.system(size: 14))
            .padding(14)
            .background(Sante.surface, in: RoundedRectangle(cornerRadius: Sante.radiusS, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Sante.radiusS).stroke(Sante.stroke))
        }
        .padding(16)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var healthInformation: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                labeledField("Peso", text: $weight, icon: "scalemass", suffix: "kg", keyboard: .decimal)
                labeledField("Altura", text: $height, icon: "ruler", suffix: "cm", keyboard: .decimal)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Tipo sanguíneo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Sante.inkSoft)
                Picker("Tipo sanguíneo", selection: $bloodType) {
                    ForEach(bloodTypes, id: \.self) { type in Text(type).tag(type) }
                }
                .pickerStyle(.menu)
                .tint(Sante.ink)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Sante.surface, in: RoundedRectangle(cornerRadius: Sante.radiusS, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Sante.radiusS).stroke(Sante.stroke))
            }

            labeledField("Alergias", text: $allergies, icon: "allergens", placeholder: "Ex.: medicamentos, alimentos", multiline: true)
            labeledField("Condições de saúde", text: $healthConditions, icon: "cross.case", placeholder: "Ex.: asma, diabetes", multiline: true)
            labeledField("Medicamentos em uso", text: $medications, icon: "pills", placeholder: "Nome e dose, se souber", multiline: true)
            labeledField("Contato de emergência", text: $emergencyContact, icon: "phone.badge.plus", placeholder: "Nome e telefone", multiline: true)

            Text("Preencha apenas o que desejar. Suas informações ficam salvas com segurança na sua conta.")
                .font(.system(size: 12))
                .foregroundStyle(Sante.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let attachments = accountStore.currentUser?.attachments, !attachments.isEmpty {
                ForEach(attachments) { attachment in
                    HStack(spacing: 11) {
                        Image(systemName: attachment.name.lowercased().hasSuffix(".pdf") ? "doc.text.fill" : "photo.fill")
                            .foregroundStyle(Sante.primary)
                            .frame(width: 38, height: 38)
                            .background(Sante.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                        Button {
                            openAttachment(attachment)
                        } label: {
                            HStack(spacing: 8) {
                                Text(attachment.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Sante.ink)
                                    .lineLimit(1)
                                if openingAttachmentID == attachment.id {
                                    ProgressView().controlSize(.small).tint(Sante.primary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(openingAttachmentID != nil)
                        Button(role: .destructive) {
                            attachmentPendingRemoval = attachment
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(Sante.inkSoft)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remover \(attachment.name)")
                    }
                    .padding(10)
                    .background(Sante.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else if uploadsInProgress == 0 {
                Text("Nenhum documento anexado ainda.")
                    .font(.system(size: 14))
                    .foregroundStyle(Sante.inkSoft)
            }

            if uploadsInProgress > 0 {
                HStack(spacing: 10) {
                    ProgressView().tint(Sante.primary)
                    Text(uploadsInProgress == 1 ? "Enviando 1 documento…" : "Enviando \(uploadsInProgress) documentos…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Sante.inkSoft)
                }
                .padding(.vertical, 4)
            }

            Button { isImportingDocuments = true } label: {
                Label("Adicionar exame ou documento", systemImage: "paperclip")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Sante.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Sante.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func avatar(size: CGFloat) -> some View {
        Group {
            if let image = currentPhotoImage {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Sante.mintDeep, .white], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(accountStore.currentUser?.initials ?? "S")
                        .font(Sante.display(size * 0.34))
                        .foregroundStyle(Sante.ink)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var currentPhotoImage: Image? {
        guard let user = accountStore.currentUser,
              let url = accountStore.profilePhotoURL(for: user),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }

    private func labeledField(
        _ title: String,
        text: Binding<String>,
        icon: String,
        placeholder: String = "",
        suffix: String? = nil,
        keyboard: KeyboardKind = .standard,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Sante.inkSoft)
            HStack(alignment: multiline ? .top : .center, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Sante.primary)
                    .frame(width: 18)
                    .padding(.top, multiline ? 3 : 0)
                TextField(placeholder, text: text, axis: multiline ? .vertical : .horizontal)
                    .font(.system(size: 15))
                    .lineLimit(multiline ? 2...4 : 1...1)
                    #if os(iOS)
                    .keyboardType(keyboardType(for: keyboard))
                    #endif
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Sante.inkSoft)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, multiline ? 13 : 0)
            .frame(minHeight: multiline ? 76 : 50)
            .background(Sante.surface, in: RoundedRectangle(cornerRadius: Sante.radiusS, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Sante.radiusS).stroke(Sante.stroke))
        }
    }

    #if os(iOS)
    private func keyboardType(for kind: KeyboardKind) -> UIKeyboardType {
        switch kind {
        case .standard: .default
        case .phone: .phonePad
        case .decimal: .decimalPad
        }
    }
    #endif

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Sante.title(21))
                .foregroundStyle(Sante.ink)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Sante.inkSoft)
        }
    }

    private func saveProfile() {
        guard !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Digite seu nome para salvar o perfil."
            return
        }
        let parsedWeight = Double(weight.replacingOccurrences(of: ",", with: "."))
        let parsedHeight = Double(height.replacingOccurrences(of: ",", with: "."))
        if !weight.trimmingCharacters(in: .whitespaces).isEmpty && (parsedWeight == nil || parsedWeight! <= 0 || parsedWeight! > 500) {
            alertMessage = "Confira o peso informado. Use um valor entre 0 e 500 kg."
            return
        }
        if !height.trimmingCharacters(in: .whitespaces).isEmpty && (parsedHeight == nil || parsedHeight! <= 0 || parsedHeight! > 300) {
            alertMessage = "Confira a altura informada. Use um valor entre 0 e 300 cm."
            return
        }
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await accountStore.updatePatientProfileRemote(
                    fullName: fullName, countryCode: countryCode, phone: phone,
                    dateOfBirth: hasDateOfBirth ? dateOfBirth : nil,
                    weightKg: parsedWeight, heightCm: parsedHeight,
                    bloodType: bloodType == "Não informado" ? "" : bloodType,
                    allergies: allergies, healthConditions: healthConditions,
                    medications: medications, emergencyContact: emergencyContact
                )
                savedDraft = currentDraft
                dismiss()
            } catch {
                alertMessage = "Não foi possível sincronizar seu perfil agora. Confira sua conexão e tente novamente."
            }
        }
    }

    private func handleDocumentImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                uploadsInProgress += 1
                Task {
                    defer { uploadsInProgress -= 1 }
                    do { _ = try await accountStore.addAttachmentRemote(from: url) }
                    catch { alertMessage = "Não foi possível sincronizar \(url.lastPathComponent). Verifique o arquivo e tente novamente." }
                }
            }
        case .failure:
            alertMessage = "Não foi possível importar os documentos selecionados."
        }
    }

    private func close() {
        if hasUnsavedChanges { showDiscardConfirmation = true } else { dismiss() }
    }

    private func openAttachment(_ attachment: PatientAttachment) {
        openingAttachmentID = attachment.id
        Task {
            defer { openingAttachmentID = nil }
            if let url = await accountStore.localURL(forRemoteAttachment: attachment) {
                previewURL = url
            } else {
                alertMessage = "Não foi possível abrir \(attachment.name). Confira sua conexão e tente novamente."
            }
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            defer { isDeletingAccount = false }
            do {
                try await accountStore.deleteAccountRemote()
                dismiss()
            } catch {
                alertMessage = "Não foi possível excluir a conta agora. Confira sua conexão e tente novamente."
            }
        }
    }

    nonisolated private static func formatMeasure(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")).grouping(.never))
    }
}

#Preview {
    PatientProfileView(accountStore: AccountStore())
}
