import Foundation

public enum APIMode: String, Codable, CaseIterable {
    case openAI = "OpenAI Responses"
    case compatible = "OpenAI 兼容 Chat Completions"
}

public struct ProviderConfiguration: Codable, Equatable {
    public var mode: APIMode
    public var baseURL: String
    public var model: String
    public init(mode: APIMode, baseURL: String, model: String) {
        self.mode = mode; self.baseURL = baseURL; self.model = model
    }
    public static let openAIDefault = ProviderConfiguration(mode: .openAI, baseURL: "https://api.openai.com/v1", model: "")
    public static let compatibleDefault = ProviderConfiguration(mode: .compatible, baseURL: "http://127.0.0.1:11434/v1", model: "")
    public func endpoint(_ path: String) throws -> URL {
        let input = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: input),
              let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else {
            throw AIError.invalidEndpoint
        }
        components.scheme = scheme
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([components.path, path].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let result = components.url else { throw AIError.invalidEndpoint }
        return result
    }
}

public struct AICandidate: Codable, Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct AIFileType: Codable, Equatable {
    public let fileExtension: String
    public let current: String?
    public let candidates: [AICandidate]
    enum CodingKeys: String, CodingKey { case fileExtension = "extension", current, candidates }
    public init(fileExtension: String, current: String?, candidates: [AICandidate]) {
        self.fileExtension = fileExtension; self.current = current; self.candidates = candidates
    }
}
public struct AIRequestContext: Codable, Equatable {
    public let preference: String
    public let types: [AIFileType]
    public init(preference: String, types: [AIFileType]) { self.preference = preference; self.types = types }
}
public struct AIRecommendation: Codable, Identifiable, Equatable {
    public let fileExtension: String
    public let candidateID: String
    public let reason: String
    public var id: String { fileExtension }
    enum CodingKeys: String, CodingKey { case fileExtension = "extension", candidateID = "candidate_id", reason }
    public init(fileExtension: String, candidateID: String, reason: String) {
        self.fileExtension = fileExtension; self.candidateID = candidateID; self.reason = reason
    }
}
public struct AIResult: Codable, Equatable {
    public let recommendations: [AIRecommendation]
    public let notes: [String]
    public init(recommendations: [AIRecommendation], notes: [String]) { self.recommendations = recommendations; self.notes = notes }
    public func validated(for context: AIRequestContext) throws -> AIResult {
        guard recommendations.count <= context.types.count, notes.count <= 10, notes.allSatisfy({ $0.count <= 300 }) else { throw AIError.invalidResult }
        var seen = Set<String>()
        for suggestion in recommendations {
            guard seen.insert(suggestion.fileExtension).inserted, !suggestion.reason.isEmpty, suggestion.reason.count <= 300,
                  let item = context.types.first(where: { $0.fileExtension == suggestion.fileExtension }),
                  item.candidates.contains(where: { $0.id == suggestion.candidateID }) else { throw AIError.invalidResult }
        }
        return self
    }
}
public enum AIError: LocalizedError {
    case invalidEndpoint, missingModel, invalidContext, invalidResult, invalidResponse, tooLarge, rejected, cancelled, network, unauthorized, rateLimited, service(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "服务地址无效。远程服务需要 HTTPS；HTTP 仅支持本机 localhost 或 127.0.0.1。"
        case .missingModel: return "请先选择或输入模型 ID。"
        case .invalidContext: return "请选择 1 至 20 个文件类型，并输入不超过 2000 字的需求。"
        case .invalidResult: return "模型返回了无效建议：包含未知类型、未知应用、重复项目或过长内容。请重试。"
        case .invalidResponse: return "服务返回的格式不受支持，或结果不完整。请检查模型和接口兼容性。"
        case .tooLarge: return "服务返回的数据过大。"
        case .rejected: return "模型拒绝了请求或没有返回建议内容。"
        case .cancelled: return "请求已取消。"
        case .network: return "无法连接服务。请检查地址、网络或证书。"
        case .unauthorized: return "服务拒绝了认证，请检查 API Key 和服务地址。"
        case .rateLimited: return "请求受到服务端限流，请稍后再试。"
        case .service(let code): return "服务返回 HTTP \(code)。请检查模型、接口兼容性或服务状态。"
        }
    }
}
