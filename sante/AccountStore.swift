import SwiftUI
import Combine
import Security
import CoreFoundation
import ImageIO
import UniformTypeIdentifiers
import Supabase

struct SanteUser: Codable, Equatable {
    var fullName: String
    let email: String
    var cpf: String? = nil
    var countryCode: String
    var phone: String
    var dateOfBirth: Date? = nil
    var weightKg: Double? = nil
    var heightCm: Double? = nil
    var bloodType: String? = nil
    var allergies: String? = nil
    var healthConditions: String? = nil
    var medications: String? = nil
    var emergencyContact: String? = nil
    var profilePhotoFileName: String? = nil
    var profilePhotoRemotePath: String? = nil
    var attachments: [PatientAttachment]? = nil

    var firstName: String {
        (fullName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? fullName).localizedCapitalized
    }

    var initials: String {
        fullName.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

struct PatientAttachment: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    let name: String
    let storedFileName: String
    var addedAt: Date = Date()
    var remotePath: String? = nil
}

enum SignupOutcome {
    case signedIn
    case needsEmailConfirmation
    case failed(String)
}

enum SignInOutcome {
    case signedIn
    case needsEmailConfirmation
    case failed(String)
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var currentUser: SanteUser?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isConnecting = false
    @Published private(set) var hasRestoredSession = false
    private var currentUserID: UUID?

    private let defaults = UserDefaults.standard
    private let profilesKey = "sante.localProfiles"
    private let sessionKey = "sante.activeEmail"
    private let keychain = SantePasswordVault()
    private var profiles: [String: SanteUser] = [:]

    init() {
        if let data = defaults.data(forKey: profilesKey),
           let savedProfiles = try? JSONDecoder().decode([String: SanteUser].self, from: data) {
            profiles = savedProfiles
        }

        defaults.removeObject(forKey: sessionKey)

        authListener = Task { [weak self] in
            for await change in SupabaseBackend.client.auth.authStateChanges {
                guard change.event == .signedOut else { continue }
                self?.signOut()
            }
        }
    }

    private var authListener: Task<Void, Never>?

    func restoreRemoteSession() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer {
            isConnecting = false
            hasRestoredSession = true
        }
        guard let session = try? await SupabaseBackend.client.auth.session else {
            currentUser = nil
            isAuthenticated = false
            return
        }
        let email = normalize(session.user.email ?? "")
        do {
            let user = try await loadRemoteUser(id: session.user.id, email: email)
            currentUser = user
            currentUserID = session.user.id
            isAuthenticated = true
            profiles[user.email] = user
            persistProfiles()
        } catch {
            if let cached = profiles[email] {
                currentUser = cached
                currentUserID = session.user.id
                isAuthenticated = true
            } else {
                currentUser = nil
                isAuthenticated = false
            }
        }
    }

    func registerRemote(fullName: String, cpf: String, email: String, countryCode: String, phone: String, password: String) async -> SignupOutcome {
        isConnecting = true
        defer { isConnecting = false }
        let normalizedEmail = normalize(email)
        let cleanedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await SupabaseBackend.client.auth.signUp(
                email: normalizedEmail,
                password: password,
                data: [
                    "full_name": .string(cleanedName),
                    "cpf": .string(cpf.filter(\.isNumber)),
                    "country_code": .string(countryCode),
                    "phone": .string(phone.filter(\.isNumber)),
                    "terms_accepted_at": .string(ISO8601DateFormatter().string(from: Date()))
                ]
            )
            guard response.session != nil else {
                return .needsEmailConfirmation
            }
            try await finishSignIn(id: response.user.id, email: normalizedEmail)
            return .signedIn
        } catch {
            return .failed(authMessage(error))
        }
    }

    func signInRemote(email: String, password: String) async -> SignInOutcome {
        isConnecting = true
        defer { isConnecting = false }
        let normalizedEmail = normalize(email)
        do {
            let session = try await SupabaseBackend.client.auth.signIn(email: normalizedEmail, password: password)
            try await finishSignIn(id: session.user.id, email: normalizedEmail)
            return .signedIn
        } catch {
            if String(describing: error).lowercased().contains("not confirmed") {
                return .needsEmailConfirmation
            }
            return .failed(authMessage(error))
        }
    }

    func confirmEmail(email: String, code: String) async -> String? {
        isConnecting = true
        defer { isConnecting = false }
        let normalizedEmail = normalize(email)
        do {
            let response = try await SupabaseBackend.client.auth.verifyOTP(
                email: normalizedEmail,
                token: code.filter(\.isNumber),
                type: .signup
            )
            try await finishSignIn(id: response.user.id, email: normalizedEmail)
            return nil
        } catch {
            return passwordResetMessage(error)
        }
    }

    func resendConfirmationCode(email: String) async -> String? {
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await SupabaseBackend.client.auth.resend(email: normalize(email), type: .signup)
            return nil
        } catch {
            return passwordResetMessage(error)
        }
    }

    private func finishSignIn(id: UUID, email: String) async throws {
        let user = try await loadRemoteUser(id: id, email: email)
        currentUser = user
        currentUserID = id
        isAuthenticated = true
        profiles[email] = user
        persistProfiles()
    }

    func sendPasswordReset(email: String) async -> String? {
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await SupabaseBackend.client.auth.resetPasswordForEmail(normalize(email))
            return nil
        } catch {
            return passwordResetMessage(error)
        }
    }

    func confirmPasswordReset(email: String, code: String, newPassword: String) async -> String? {
        isConnecting = true
        defer { isConnecting = false }
        let normalizedEmail = normalize(email)
        let client = SupabaseBackend.client
        do {
            let response = try await client.auth.verifyOTP(
                email: normalizedEmail,
                token: code.filter(\.isNumber),
                type: .recovery
            )
            try await client.auth.update(user: UserAttributes(password: newPassword))
            try await finishSignIn(id: response.user.id, email: normalizedEmail)
            return nil
        } catch {
            return passwordResetMessage(error)
        }
    }

    private func passwordResetMessage(_ error: Error) -> String {
        let detail = String(describing: error).lowercased()
        if detail.contains("rate limit") || detail.contains("too many") || detail.contains("429") || detail.contains("security purposes") {
            return "Muitas tentativas seguidas. Aguarde alguns minutos e tente novamente."
        }
        if detail.contains("same") && detail.contains("password") {
            return "A nova senha precisa ser diferente da anterior."
        }
        if detail.contains("weak") || detail.contains("password should") {
            return "Essa senha é fraca demais. Escolha outra mais forte."
        }
        if detail.contains("expired") || detail.contains("invalid") || detail.contains("otp") || detail.contains("token") {
            return "Código inválido ou expirado. Confira o código ou peça um novo."
        }
        return "Não foi possível conectar agora. Confira sua conexão e tente novamente."
    }

    func signOutRemote() async {
        try? await SupabaseBackend.client.auth.signOut()
        signOut()
    }

    func register(fullName: String, email: String, countryCode: String, phone: String, password: String) -> String? {
        let normalizedEmail = normalize(email)
        let cleanedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard profiles[normalizedEmail] == nil else {
            return "Já existe uma conta com esse e-mail neste dispositivo. Entre nela ou use outro e-mail."
        }

        let user = SanteUser(
            fullName: cleanedName,
            email: normalizedEmail,
            countryCode: countryCode,
            phone: phone.filter(\.isNumber)
        )

        guard keychain.save(password, for: normalizedEmail) else {
            return "Não foi possível proteger sua senha neste dispositivo. Tente novamente."
        }

        profiles[normalizedEmail] = user
        persistProfiles()
        startSession(for: user)
        return nil
    }

    func signIn(email: String, password: String) -> String? {
        let normalizedEmail = normalize(email)
        guard let user = profiles[normalizedEmail] else {
            return "Não encontramos uma conta com esse e-mail neste dispositivo. Confira os dados ou crie uma conta."
        }
        guard let savedPassword = keychain.password(for: normalizedEmail), savedPassword == password else {
            return "E-mail ou senha incorretos. Confira os dados e tente novamente."
        }

        startSession(for: user)
        return nil
    }

    func signOut() {
        if let email = currentUser?.email {
            profiles[email] = nil
            persistProfiles()
        }
        currentUser = nil
        currentUserID = nil
        isAuthenticated = false
        defaults.removeObject(forKey: sessionKey)
        for folder in ["profile-photos", "patient-documents"] {
            if let directory = try? storageDirectory(named: folder) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    func deleteAccountRemote() async throws {
        guard let userID = currentUserID else { throw ProfileStorageError.noActiveAccount }
        let client = SupabaseBackend.client
        let folder = userID.uuidString
        for bucket in ["patient-documents", "profile-photos"] {
            let files = (try? await client.storage.from(bucket).list(path: folder)) ?? []
            let paths = files.map { "\(folder)/\($0.name)" }
            if !paths.isEmpty {
                _ = try await client.storage.from(bucket).remove(paths: paths)
            }
        }
        try await client.rpc("delete_own_account").execute()
        try? await client.auth.signOut()
        signOut()
    }

    func updatePatientProfile(
        fullName: String,
        countryCode: String,
        phone: String,
        dateOfBirth: Date?,
        weightKg: Double?,
        heightCm: Double?,
        bloodType: String,
        allergies: String,
        healthConditions: String,
        medications: String,
        emergencyContact: String
    ) {
        guard let email = currentUser?.email, var user = profiles[email] else { return }
        user.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        user.countryCode = countryCode
        user.phone = phone.filter(\.isNumber)
        user.dateOfBirth = dateOfBirth
        user.weightKg = weightKg
        user.heightCm = heightCm
        user.bloodType = optionalValue(bloodType)
        user.allergies = optionalValue(allergies)
        user.healthConditions = optionalValue(healthConditions)
        user.medications = optionalValue(medications)
        user.emergencyContact = optionalValue(emergencyContact)
        save(user)
    }

    func updatePatientProfileRemote(
        fullName: String, countryCode: String, phone: String, dateOfBirth: Date?,
        weightKg: Double?, heightCm: Double?, bloodType: String,
        allergies: String, healthConditions: String, medications: String, emergencyContact: String
    ) async throws {
        guard var user = currentUser, let userID = currentUserID else { throw ProfileStorageError.noActiveAccount }
        user.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        user.countryCode = countryCode
        user.phone = phone.filter(\.isNumber)
        user.dateOfBirth = dateOfBirth
        user.weightKg = weightKg
        user.heightCm = heightCm
        user.bloodType = optionalValue(bloodType)
        user.allergies = optionalValue(allergies)
        user.healthConditions = optionalValue(healthConditions)
        user.medications = optionalValue(medications)
        user.emergencyContact = optionalValue(emergencyContact)

        let profile = ProfileUpdate(
            display_name: user.fullName, cpf: user.cpf, country_code: user.countryCode, phone: user.phone,
            date_of_birth: user.dateOfBirth.map(Self.dateString), profile_photo_path: user.profilePhotoRemotePath
        )
        let health = HealthProfileUpdate(
            weight_kg: user.weightKg, height_cm: user.heightCm,
            blood_type: user.bloodType?.replacingOccurrences(of: "−", with: "-"),
            allergies: user.allergies, health_conditions: user.healthConditions,
            medications: user.medications, emergency_contact: user.emergencyContact
        )
        try await SupabaseBackend.client.from("profiles").update(profile)
            .eq("user_id", value: userID.uuidString).execute()
        try await SupabaseBackend.client.from("health_profiles").update(health)
            .eq("user_id", value: userID.uuidString).execute()
        save(user)
    }

    func updateProfilePhotoRemote(_ imageData: Data) async throws {
        guard let userID = currentUserID, var user = currentUser,
              let thumbnail = makePhotoThumbnail(imageData) else { throw ProfileStorageError.noActiveAccount }
        let previousRemotePath = user.profilePhotoRemotePath
        let remotePath = "\(userID.uuidString)/\(UUID().uuidString).jpg"
        try await SupabaseBackend.client.storage.from("profile-photos").upload(
            remotePath, data: thumbnail,
            options: FileOptions(contentType: "image/jpeg", upsert: false)
        )
        updateProfilePhoto(thumbnail)
        user = currentUser ?? user
        user.profilePhotoRemotePath = remotePath
        save(user)
        let update = ProfileUpdate(
            display_name: user.fullName, cpf: user.cpf, country_code: user.countryCode, phone: user.phone,
            date_of_birth: user.dateOfBirth.map(Self.dateString), profile_photo_path: remotePath
        )
        try await SupabaseBackend.client.from("profiles").update(update)
            .eq("user_id", value: userID.uuidString).execute()
        if let previousRemotePath, previousRemotePath != remotePath {
            _ = try? await SupabaseBackend.client.storage.from("profile-photos").remove(paths: [previousRemotePath])
        }
    }

    func removeProfilePhotoRemote() async throws {
        guard let userID = currentUserID, var user = currentUser else { throw ProfileStorageError.noActiveAccount }
        if let path = user.profilePhotoRemotePath {
            try await SupabaseBackend.client.storage.from("profile-photos").remove(paths: [path])
        }
        removeProfilePhoto()
        user = currentUser ?? user
        user.profilePhotoRemotePath = nil
        save(user)
        let update = ProfileUpdate(
            display_name: user.fullName, cpf: user.cpf, country_code: user.countryCode, phone: user.phone,
            date_of_birth: user.dateOfBirth.map(Self.dateString), profile_photo_path: nil
        )
        try await SupabaseBackend.client.from("profiles").update(update)
            .eq("user_id", value: userID.uuidString).execute()
    }

    func addAttachmentRemote(from sourceURL: URL) async throws -> PatientAttachment {
        guard let userID = currentUserID else { throw ProfileStorageError.noActiveAccount }
        let attachment = try addAttachment(from: sourceURL)
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: sourceURL)
        let remotePath = "\(userID.uuidString)/\(attachment.storedFileName)"
        let mime = UTType(filenameExtension: sourceURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        do {
            try await SupabaseBackend.client.storage.from("patient-documents").upload(
                remotePath, data: data,
                options: FileOptions(contentType: mime, upsert: false)
            )
            let record = DocumentInsert(
                user_id: userID, object_path: remotePath, display_name: attachment.name,
                mime_type: mime, file_size_bytes: data.count
            )
            try await SupabaseBackend.client.from("patient_documents").insert(record).execute()
        } catch {
            _ = try? await SupabaseBackend.client.storage.from("patient-documents").remove(paths: [remotePath])
            removeAttachment(attachment)
            throw error
        }
        if var user = currentUser, let index = user.attachments?.firstIndex(where: { $0.id == attachment.id }) {
            user.attachments?[index].remotePath = remotePath
            save(user)
        }
        return currentUser?.attachments?.first(where: { $0.id == attachment.id }) ?? attachment
    }

    func removeAttachmentRemote(_ attachment: PatientAttachment) async throws {
        guard let userID = currentUserID else { throw ProfileStorageError.noActiveAccount }
        if let remotePath = attachment.remotePath {
            try await SupabaseBackend.client.storage.from("patient-documents").remove(paths: [remotePath])
            try await SupabaseBackend.client.from("patient_documents").delete()
                .eq("user_id", value: userID.uuidString).eq("object_path", value: remotePath).execute()
        }
        removeAttachment(attachment)
    }

    func localURL(forRemoteAttachment attachment: PatientAttachment) async -> URL? {
        if let local = attachmentURL(for: attachment) { return local }
        guard let remotePath = attachment.remotePath,
              let data = try? await SupabaseBackend.client.storage.from("patient-documents").download(path: remotePath),
              let directory = try? storageDirectory(named: "patient-documents") else { return nil }
        let destination = directory.appendingPathComponent(attachment.storedFileName)
        try? data.write(to: destination, options: .atomic)
        return FileManager.default.fileExists(atPath: destination.path) ? destination : nil
    }

    func updateProfilePhoto(_ imageData: Data) {
        guard let email = currentUser?.email, var user = profiles[email],
              let thumbnail = makePhotoThumbnail(imageData) else { return }
        do {
            let directory = try storageDirectory(named: "profile-photos")
            let fileName = "\(UUID().uuidString).jpg"
            try thumbnail.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            let previousPhoto = user.profilePhotoFileName
            user.profilePhotoFileName = fileName
            save(user)
            if let previousPhoto { try? FileManager.default.removeItem(at: directory.appendingPathComponent(previousPhoto)) }
        } catch {
            return
        }
    }

    func removeProfilePhoto() {
        guard let email = currentUser?.email, var user = profiles[email] else { return }
        let oldPhoto = user.profilePhotoFileName
        user.profilePhotoFileName = nil
        save(user)
        if let oldPhoto, let directory = try? storageDirectory(named: "profile-photos") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldPhoto))
        }
    }

    func profilePhotoURL(for user: SanteUser) -> URL? {
        guard let fileName = user.profilePhotoFileName,
              let directory = try? storageDirectory(named: "profile-photos") else { return nil }
        let url = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func addAttachment(from sourceURL: URL) throws -> PatientAttachment {
        guard let email = currentUser?.email, var user = profiles[email] else {
            throw ProfileStorageError.noActiveAccount
        }
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let directory = try storageDirectory(named: "patient-documents")
        let ext = sourceURL.pathExtension
        let storedName = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(storedName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let attachment = PatientAttachment(name: sourceURL.lastPathComponent, storedFileName: storedName)
        user.attachments = (user.attachments ?? []) + [attachment]
        save(user)
        return attachment
    }

    func removeAttachment(_ attachment: PatientAttachment) {
        guard let email = currentUser?.email, var user = profiles[email] else { return }
        user.attachments = (user.attachments ?? []).filter { $0.id != attachment.id }
        save(user)
        if let directory = try? storageDirectory(named: "patient-documents") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(attachment.storedFileName))
        }
    }

    func attachmentURL(for attachment: PatientAttachment) -> URL? {
        guard let directory = try? storageDirectory(named: "patient-documents") else { return nil }
        let url = directory.appendingPathComponent(attachment.storedFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func startSession(for user: SanteUser) {
        currentUser = user
        isAuthenticated = true
        defaults.set(user.email, forKey: sessionKey)
    }

    private func save(_ user: SanteUser) {
        profiles[user.email] = user
        persistProfiles()
        currentUser = user
    }

    private func optionalValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func storageDirectory(named name: String) throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Sante", isDirectory: true)
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePhotoThumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: profilesKey)
    }

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func loadRemoteUser(id: UUID, email: String) async throws -> SanteUser {
        let client = SupabaseBackend.client
        try await ensureProfileRows(id: id)
        let profile: ProfileRecord = try await client.from("profiles").select()
            .eq("user_id", value: id.uuidString).single().execute().value
        let health: HealthProfileRecord = try await client.from("health_profiles").select()
            .eq("user_id", value: id.uuidString).single().execute().value
        let documents: [DocumentRecord] = try await client.from("patient_documents").select()
            .eq("user_id", value: id.uuidString).order("created_at", ascending: false).execute().value

        var user = SanteUser(
            fullName: profile.display_name, email: email, cpf: profile.cpf, countryCode: profile.country_code,
            phone: profile.phone ?? "", dateOfBirth: profile.date_of_birth.flatMap(Self.parseDate),
            weightKg: health.weight_kg, heightCm: health.height_cm,
            bloodType: health.blood_type?.replacingOccurrences(of: "-", with: "−"),
            allergies: health.allergies, healthConditions: health.health_conditions,
            medications: health.medications, emergencyContact: health.emergency_contact,
            profilePhotoRemotePath: profile.profile_photo_path,
            attachments: documents.map {
                PatientAttachment(id: $0.id, name: $0.display_name,
                                  storedFileName: URL(fileURLWithPath: $0.object_path).lastPathComponent,
                                  remotePath: $0.object_path)
            }
        )

        if let photoPath = profile.profile_photo_path,
           let data = try? await client.storage.from("profile-photos").download(path: photoPath),
           let thumbnail = makePhotoThumbnail(data),
           let directory = try? storageDirectory(named: "profile-photos") {
            let fileName = "\(UUID().uuidString).jpg"
            try? thumbnail.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            user.profilePhotoFileName = fileName
        }
        return user
    }

    private func ensureProfileRows(id: UUID) async throws {
        let client = SupabaseBackend.client
        let existing: [UserIDRecord] = try await client.from("profiles").select("user_id")
            .eq("user_id", value: id.uuidString).limit(1).execute().value
        let existingHealth: [UserIDRecord] = try await client.from("health_profiles").select("user_id")
            .eq("user_id", value: id.uuidString).limit(1).execute().value
        guard existing.isEmpty || existingHealth.isEmpty else { return }

        let metadata = client.auth.currentUser?.userMetadata ?? [:]
        func text(_ key: String) -> String? {
            if case let .string(value)? = metadata[key], !value.isEmpty { return value }
            return nil
        }
        if existing.isEmpty {
            let row = ProfileInsert(
                user_id: id,
                display_name: text("full_name") ?? "",
                cpf: text("cpf"),
                country_code: text("country_code") ?? "+55",
                phone: text("phone")
            )
            try await client.from("profiles").upsert(row, onConflict: "user_id", ignoreDuplicates: true).execute()
        }
        if existingHealth.isEmpty {
            try await client.from("health_profiles")
                .upsert(UserIDRecord(user_id: id), onConflict: "user_id", ignoreDuplicates: true).execute()
        }
    }

    private func authMessage(_ error: Error) -> String {
        let detail = String(describing: error).lowercased()
        if detail.contains("invalid login") || detail.contains("invalid_credentials") {
            return "E-mail ou senha incorretos. Confira os dados e tente novamente."
        }
        if detail.contains("email not confirmed") {
            return "Confirme seu e-mail pelo link enviado antes de entrar."
        }
        if detail.contains("already registered") || detail.contains("user already registered") {
            return "Este e-mail já possui uma conta. Entre nela ou use outro e-mail."
        }
        return "Não foi possível conectar à conta agora. Confira sua conexão e tente novamente."
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

nonisolated private struct UserIDRecord: Codable {
    let user_id: UUID
}

nonisolated private struct ProfileInsert: Encodable {
    let user_id: UUID
    let display_name: String
    let cpf: String?
    let country_code: String
    let phone: String?
}

nonisolated private struct ProfileRecord: Decodable {
    let display_name: String
    let cpf: String?
    let country_code: String
    let phone: String?
    let date_of_birth: String?
    let profile_photo_path: String?
}

nonisolated private struct HealthProfileRecord: Decodable {
    let weight_kg: Double?
    let height_cm: Double?
    let blood_type: String?
    let allergies: String?
    let health_conditions: String?
    let medications: String?
    let emergency_contact: String?
}

nonisolated private struct DocumentRecord: Decodable {
    let id: UUID
    let object_path: String
    let display_name: String
}

nonisolated private struct ProfileUpdate: Encodable {
    let display_name: String
    let cpf: String?
    let country_code: String
    let phone: String?
    let date_of_birth: String?
    let profile_photo_path: String?

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(display_name, forKey: .display_name)
        try Self.encodeNullable(cpf, to: &values, key: .cpf)
        try values.encode(country_code, forKey: .country_code)
        try Self.encodeNullable(phone, to: &values, key: .phone)
        try Self.encodeNullable(date_of_birth, to: &values, key: .date_of_birth)
        try Self.encodeNullable(profile_photo_path, to: &values, key: .profile_photo_path)
    }

    private enum CodingKeys: String, CodingKey { case display_name, cpf, country_code, phone, date_of_birth, profile_photo_path }

    private static func encodeNullable<T: Encodable>(_ value: T?, to container: inout KeyedEncodingContainer<CodingKeys>, key: CodingKeys) throws {
        if let value { try container.encode(value, forKey: key) } else { try container.encodeNil(forKey: key) }
    }
}

nonisolated private struct HealthProfileUpdate: Encodable {
    let weight_kg: Double?
    let height_cm: Double?
    let blood_type: String?
    let allergies: String?
    let health_conditions: String?
    let medications: String?
    let emergency_contact: String?

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodeNullable(weight_kg, to: &values, key: .weight_kg)
        try Self.encodeNullable(height_cm, to: &values, key: .height_cm)
        try Self.encodeNullable(blood_type, to: &values, key: .blood_type)
        try Self.encodeNullable(allergies, to: &values, key: .allergies)
        try Self.encodeNullable(health_conditions, to: &values, key: .health_conditions)
        try Self.encodeNullable(medications, to: &values, key: .medications)
        try Self.encodeNullable(emergency_contact, to: &values, key: .emergency_contact)
    }

    private enum CodingKeys: String, CodingKey { case weight_kg, height_cm, blood_type, allergies, health_conditions, medications, emergency_contact }

    private static func encodeNullable<T: Encodable>(_ value: T?, to container: inout KeyedEncodingContainer<CodingKeys>, key: CodingKeys) throws {
        if let value { try container.encode(value, forKey: key) } else { try container.encodeNil(forKey: key) }
    }
}

nonisolated private struct DocumentInsert: Encodable {
    let user_id: UUID
    let object_path: String
    let display_name: String
    let mime_type: String
    let file_size_bytes: Int
}

private enum ProfileStorageError: Error {
    case noActiveAccount
}

private struct SantePasswordVault {
    private let service = "com.sante.local-account-passwords"

    func save(_ password: String, for email: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    func password(for email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
