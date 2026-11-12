import Foundation

public struct ChangeProposal {
    public let fileExtension: String
    public let typeID: String
    public let target: String
    public let current: String?
    public init(fileExtension: String, typeID: String, target: String, current: String?) {
        self.fileExtension = fileExtension; self.typeID = typeID; self.target = target; self.current = current
    }
}
public enum ChangeGroupingError: Error { case conflictingTargets, inconsistentCurrent }
public enum ChangeGrouping {
    // Multiple extensions can resolve to the same system type. Apply that type only once.
    public static func group(_ proposals: [ChangeProposal]) throws -> [[String]] {
        var groups: [[ChangeProposal]] = []
        for proposal in proposals {
            if let index = groups.firstIndex(where: { $0[0].typeID == proposal.typeID }) {
                guard groups[index][0].target == proposal.target else { throw ChangeGroupingError.conflictingTargets }
                guard groups[index][0].current == proposal.current else { throw ChangeGroupingError.inconsistentCurrent }
                groups[index].append(proposal)
            } else { groups.append([proposal]) }
        }
        return groups.map { $0.map(\.fileExtension) }
    }
}
