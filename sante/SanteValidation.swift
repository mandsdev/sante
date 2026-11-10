import Foundation

enum SanteValidation {
    static func cpfDigits(_ cpf: String) -> String { cpf.filter(\.isNumber) }

    static func isValidCPF(_ cpf: String) -> Bool {
        let numbers = cpfDigits(cpf)
        guard numbers.count == 11, Set(numbers).count > 1 else { return false }
        let digits = numbers.compactMap { Int(String($0)) }
        guard digits.count == 11 else { return false }

        func checkDigit(upTo count: Int) -> Int {
            var sum = 0
            for index in 0..<count { sum += digits[index] * (count + 1 - index) }
            let digit = 11 - (sum % 11)
            return digit >= 10 ? 0 : digit
        }
        return checkDigit(upTo: 9) == digits[9] && checkDigit(upTo: 10) == digits[10]
    }

    static func isValidEmail(_ email: String) -> Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !value.contains(" ") else { return false }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."), dot != domain.startIndex else { return false }
        return !domain[domain.index(after: dot)...].isEmpty
    }

    static func isValidPhone(_ phone: String) -> Bool {
        phone.filter(\.isNumber).count >= 8
    }

    struct PasswordCheck: Equatable {
        let hasMinLength: Bool
        let hasUppercase: Bool
        let hasSpecialChar: Bool
        var isValid: Bool { hasMinLength && hasUppercase && hasSpecialChar }
    }

    static func checkPassword(_ password: String) -> PasswordCheck {
        PasswordCheck(
            hasMinLength: password.count >= 6,
            hasUppercase: password.range(of: "[A-Z]", options: .regularExpression) != nil,
            hasSpecialChar: password.range(of: "[^a-zA-Z0-9]", options: .regularExpression) != nil
        )
    }

    static func isValidCode(_ code: String) -> Bool {
        (6...10).contains(code.filter(\.isNumber).count)
    }
}
