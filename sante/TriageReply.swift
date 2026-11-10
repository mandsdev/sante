import Foundation

struct TriageReply {
    let isComplete: Bool
    let report: String?

    init(text: String) {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        isComplete = normalized.contains("agende sua consulta")

        guard isComplete,
              let titleRange = text.range(of: "resumo para a consulta", options: [.caseInsensitive, .diacriticInsensitive]),
              let invitationRange = text[titleRange.upperBound...].range(of: "agende sua consulta", options: [.caseInsensitive, .diacriticInsensitive])
        else {
            report = nil
            return
        }

        let summary = text[titleRange.upperBound..<invitationRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—*#")))
        report = summary.isEmpty ? nil : "Resumo para a consulta\n\(summary)"
    }
}
