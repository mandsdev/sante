import XCTest
@testable import sante

@MainActor
final class SanteValidationTests: XCTestCase {
    func testValidCPFsAreAcceptedWithOrWithoutFormatting() {
        XCTAssertTrue(SanteValidation.isValidCPF("529.982.247-25"))
        XCTAssertTrue(SanteValidation.isValidCPF("52998224725"))
        XCTAssertTrue(SanteValidation.isValidCPF("111.444.777-35"))
    }

    func testCPFWithWrongCheckDigitIsRejected() {
        XCTAssertFalse(SanteValidation.isValidCPF("529.982.247-24"))
    }

    func testCPFWithAllDigitsEqualIsRejected() {
        XCTAssertFalse(SanteValidation.isValidCPF("111.111.111-11"))
        XCTAssertFalse(SanteValidation.isValidCPF("000.000.000-00"))
    }

    func testIncompleteOrEmptyCPFIsRejected() {
        XCTAssertFalse(SanteValidation.isValidCPF(""))
        XCTAssertFalse(SanteValidation.isValidCPF("123"))
        XCTAssertFalse(SanteValidation.isValidCPF("529.982.247-2"))
        XCTAssertFalse(SanteValidation.isValidCPF("abc.def.ghi-jk"))
    }

    func testCPFDigitsRemovesFormatting() {
        XCTAssertEqual(SanteValidation.cpfDigits("529.982.247-25"), "52998224725")
    }

    func testValidEmailsAreAccepted() {
        XCTAssertTrue(SanteValidation.isValidEmail("ana@gmail.com"))
        XCTAssertTrue(SanteValidation.isValidEmail("ana.silva@empresa.com.br"))
        XCTAssertTrue(SanteValidation.isValidEmail("a+b@x.io"))
    }

    func testSpacesAroundEmailAreIgnored() {
        XCTAssertTrue(SanteValidation.isValidEmail("  ana@gmail.com  "))
    }

    func testEmailWithoutDotInDomainIsRejected() {
        XCTAssertFalse(SanteValidation.isValidEmail("nome.sobrenome@gmail"))
    }

    func testMalformedEmailsAreRejected() {
        XCTAssertFalse(SanteValidation.isValidEmail(""))
        XCTAssertFalse(SanteValidation.isValidEmail("ana@"))
        XCTAssertFalse(SanteValidation.isValidEmail("@gmail.com"))
        XCTAssertFalse(SanteValidation.isValidEmail("ana@@gmail.com"))
        XCTAssertFalse(SanteValidation.isValidEmail("ana @gmail.com"))
        XCTAssertFalse(SanteValidation.isValidEmail("ana@.com"))
        XCTAssertFalse(SanteValidation.isValidEmail("ana@gmail."))
    }

    func testPhoneCountsOnlyDigits() {
        XCTAssertTrue(SanteValidation.isValidPhone("(11) 98765-4321"))
        XCTAssertTrue(SanteValidation.isValidPhone("1234 5678"))
        XCTAssertFalse(SanteValidation.isValidPhone("1234-567"))
        XCTAssertFalse(SanteValidation.isValidPhone("(  ) -"))
    }

    func testPasswordWithAllRulesIsValid() {
        let check = SanteValidation.checkPassword("Senha@1")
        XCTAssertTrue(check.hasMinLength)
        XCTAssertTrue(check.hasUppercase)
        XCTAssertTrue(check.hasSpecialChar)
        XCTAssertTrue(check.isValid)
    }

    func testPasswordWithoutUppercaseIsInvalid() {
        let check = SanteValidation.checkPassword("senha@1")
        XCTAssertFalse(check.hasUppercase)
        XCTAssertFalse(check.isValid)
    }

    func testPasswordWithoutSymbolIsInvalid() {
        let check = SanteValidation.checkPassword("Senha12")
        XCTAssertFalse(check.hasSpecialChar)
        XCTAssertFalse(check.isValid)
    }

    func testShortPasswordIsInvalid() {
        let check = SanteValidation.checkPassword("S@1")
        XCTAssertFalse(check.hasMinLength)
        XCTAssertFalse(check.isValid)
    }

    func testEmptyPasswordFailsEveryRule() {
        XCTAssertEqual(
            SanteValidation.checkPassword(""),
            SanteValidation.PasswordCheck(hasMinLength: false, hasUppercase: false, hasSpecialChar: false)
        )
    }

    func testCodeNeedsSixToTenDigits() {
        XCTAssertTrue(SanteValidation.isValidCode("123456"))
        XCTAssertTrue(SanteValidation.isValidCode("1234567890"))
        XCTAssertTrue(SanteValidation.isValidCode("123 456"))
        XCTAssertFalse(SanteValidation.isValidCode("12345"))
        XCTAssertFalse(SanteValidation.isValidCode("12345678901"))
        XCTAssertFalse(SanteValidation.isValidCode(""))
    }
}
