import Foundation

public enum ChangeDecision: Equatable {
    case allowed, typeChanged, currentChanged, missingApplication, unsupportedApplication
}
public enum ChangeGuard {
    public static func evaluate(expectedType: String, actualType: String?, expectedCurrent: String?, actualCurrent: String?, target: String, candidates: Set<String>, targetExists: Bool) -> ChangeDecision {
        guard actualType == expectedType else { return .typeChanged }
        guard actualCurrent == expectedCurrent else { return .currentChanged }
        guard targetExists else { return .missingApplication }
        guard candidates.contains(target) || actualCurrent == target else { return .unsupportedApplication }
        return .allowed
    }
}
