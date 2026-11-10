import XCTest
@testable import sante

@MainActor
final class EmergencyAlertTests: XCTestCase {
    private let medicalEmergencies = [
        "Estou com uma dor muito forte no peito que vai pro braço esquerdo",
        "Sinto um aperto no peito quando fico nervosa",
        "Tô sem ar",
        "Estou com falta de ar desde cedo",
        "Meu rosto ficou torto de repente",
        "Minha boca está torta e não consigo falar direito",
        "Minha garganta tá fechando depois que comi camarão",
        "Vomitei sangue hoje",
        "Meu filho teve uma convulsão",
        "Desmaiei no banheiro agora há pouco",
        "Estou sangrando muito e não para"
    ]

    private let selfHarm = [
        "Não aguento mais, tô pensando em tirar minha vida",
        "Eu quero morrer",
        "Tenho pensado em me machucar"
    ]

    private let notEmergencies = [
        "Estou com dor de garganta desde ontem",
        "Tô com dor de cabeça e enjoo",
        "Dor nas costas quando ando",
        "Tenho febre e dor no corpo",
        "Tô com tosse e catarro",
        "Estou com diarreia",
        "Oi"
    ]

    func testMedicalEmergenciesShowTheSAMUAlert() {
        for phrase in medicalEmergencies {
            let alert = EmergencyAlert.check(phrase)
            XCTAssertNotNil(alert, "Deveria detectar emergência em: \(phrase)")
            XCTAssertEqual(alert?.includesCVV, false, "Emergência médica não precisa do CVV: \(phrase)")
        }
    }

    func testSelfHarmShowsCVVTogetherWithSAMU() {
        for phrase in selfHarm {
            let alert = EmergencyAlert.check(phrase)
            XCTAssertNotNil(alert, "Deveria detectar risco em: \(phrase)")
            XCTAssertEqual(alert?.includesCVV, true, "Deveria oferecer o CVV em: \(phrase)")
        }
    }

    func testOrdinarySymptomsDoNotTriggerTheAlert() {
        for phrase in notEmergencies {
            XCTAssertNil(EmergencyAlert.check(phrase), "Não deveria ser emergência: \(phrase)")
        }
    }

    func testDetectionIgnoresAccentsAndCapitalLetters() {
        XCTAssertNotNil(EmergencyAlert.check("DOR NO PEITO"))
        XCTAssertNotNil(EmergencyAlert.check("convulsao"))
        XCTAssertNotNil(EmergencyAlert.check("Não Consigo Respirar"))
    }

    func testRepliesPointToTheRightPhoneNumbers() {
        let medical = EmergencyAlert.check("dor no peito")
        XCTAssertTrue(medical?.reply.contains("192") == true)
        XCTAssertTrue(medical?.message.contains("192") == true)

        let risk = EmergencyAlert.check("quero morrer")
        XCTAssertTrue(risk?.reply.contains("188") == true)
        XCTAssertTrue(risk?.reply.contains("192") == true)
    }
}
