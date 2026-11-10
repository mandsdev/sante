import XCTest
@testable import sante

@MainActor
final class TriageReplyTests: XCTestCase {
    func testQuestionDoesNotCompleteTriageOrCreateReport() {
        let result = TriageReply(text: "Quando começou a dor?")

        XCTAssertFalse(result.isComplete)
        XCTAssertNil(result.report)
    }

    func testCompletionInvitationAndSummaryCreateReport() {
        let result = TriageReply(text: "**Resumo para a consulta**\nDor de cabeça desde ontem.\n\nAgende sua consulta no aplicativo Sante.")

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.report, "Resumo para a consulta\nDor de cabeça desde ontem.")
    }

    func testInvitationWithoutSummaryCompletesButDoesNotSendAnEmptyReport() {
        let result = TriageReply(text: "Agende sua consulta no aplicativo Sante.")

        XCTAssertTrue(result.isComplete)
        XCTAssertNil(result.report)
    }

    func testEmergencyAdviceDoesNotCompleteTheBookingFlow() {
        let result = TriageReply(text: "Isso pode ser uma emergência. Ligue para o SAMU no 192 agora.")

        XCTAssertFalse(result.isComplete)
        XCTAssertNil(result.report)
    }

    func testTitleWithColonAndMarkdownIsCleanedFromTheReport() {
        let result = TriageReply(text: "## Resumo para a consulta:\nFebre de 38 graus há dois dias.\n\nAgende sua consulta no aplicativo Sante.")

        XCTAssertEqual(result.report, "Resumo para a consulta\nFebre de 38 graus há dois dias.")
    }

    func testMatchingIgnoresAccentsAndCapitalLetters() {
        let result = TriageReply(text: "RESUMO PARA A CONSULTA\nTosse seca.\nAGENDE SUA CONSULTA no app.")

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.report, "Resumo para a consulta\nTosse seca.")
    }

    func testRealModelAnswerProducesTheSummary() {
        let answer = """
        Ok, entendi que foi só isso mesmo para te entender hoje.

        **Resumo para a consulta:**
        A paciente relata dor de cabeça começando ontem à noite, que não passou e persiste hoje. A dor localiza-se no lado direito da testa e é classificada como forte (7 de 10), piorando com a exposição à luz.

        Agende sua consulta no aplicativo Sante.
        """
        let result = TriageReply(text: answer)

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.report?.hasPrefix("Resumo para a consulta\nA paciente relata dor de cabeça"), true)
        XCTAssertEqual(result.report?.contains("Agende"), false)
    }
}
