import Foundation
import OpenKindCore

private struct MockTransport: HTTPTransport {
    let handler: (URLRequest) throws -> (Data, HTTPURLResponse)
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { try handler(request) }
}
private func response(_ request: URLRequest, status: Int = 200, object: Any) throws -> (Data, HTTPURLResponse) {
    (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}
private func assertCheck(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
private func expectsError(_ message: String, _ body: () throws -> Void) {
    do { try body(); fputs("FAIL: \(message)\n", stderr); exit(1) } catch { }
}
func runAIChecks() async throws {
    for (code, expected) in [(NSURLErrorTimedOut, "timeout"), (NSURLErrorCannotFindHost, "dns"), (NSURLErrorCannotConnectToHost, "connection"), (NSURLErrorServerCertificateUntrusted, "tls"), (NSURLErrorCancelled, "cancelled")] {
        switch (SafeHTTPTransport.networkError(for: NSError(domain: NSURLErrorDomain, code: code)), expected) {
        case (.timeout, "timeout"), (.dns, "dns"), (.connection, "connection"), (.tls, "tls"), (.cancelled, "cancelled"): break
        default: fputs("FAIL: network error classification\n", stderr); exit(1)
        }
    }
    let official = ProviderConfiguration(mode: .openAI, baseURL: "https://api.openai.com/v1/", model: "test-model")
    let modelsURL = try official.endpoint("models")
    assertCheck(modelsURL.absoluteString == "https://api.openai.com/v1/models", "construct model endpoint")
    let local = ProviderConfiguration(mode: .compatible, baseURL: "http://127.0.0.1:1234/v1", model: "model")
    let chatURL = try local.endpoint("chat/completions")
    assertCheck(chatURL.path == "/v1/chat/completions", "construct compatible endpoint")
    for value in ["http://example.com/v1", "https://user:pass@example.com/v1", "https://example.com/v1?key=x", "file:///tmp/a"] {
        expectsError("reject unsafe endpoint \(value)") { _ = try ProviderConfiguration(mode: .compatible, baseURL: value, model: "x").endpoint("models") }
    }
    let item = AIFileType(fileExtension: "vue", current: "Editor", candidates: [AICandidate(id: "example.editor", name: "Editor")])
    let context = AIRequestContext(preference: "用 Editor", types: [item])
    let valid = AIResult(recommendations: [AIRecommendation(fileExtension: "vue", candidateID: "example.editor", reason: "支持 Vue")], notes: [])
    _ = try valid.validated(for: context)
    expectsError("reject unknown extension") { _ = try AIResult(recommendations: [AIRecommendation(fileExtension: "docx", candidateID: "example.editor", reason: "x")], notes: []).validated(for: context) }
    expectsError("reject unknown candidate") { _ = try AIResult(recommendations: [AIRecommendation(fileExtension: "vue", candidateID: "evil.app", reason: "x")], notes: []).validated(for: context) }
    expectsError("reject duplicate recommendations") { _ = try AIResult(recommendations: valid.recommendations + valid.recommendations, notes: []).validated(for: context) }
    let output = String(data: try JSONEncoder().encode(valid), encoding: .utf8)!
    let transport = MockTransport { request in
        assertCheck(request.url!.path == "/v1/responses", "OpenAI Responses endpoint")
        assertCheck(request.timeoutInterval == 300, "generation gets a longer per-request timeout")
        assertCheck(request.value(forHTTPHeaderField: "Authorization") == "Bearer dummy-test-key", "authorization header")
        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        assertCheck(json["store"] as? Bool == false, "disable stored response")
        assertCheck(json["text"] != nil, "request structured output")
        assertCheck(!String(data: request.httpBody!, encoding: .utf8)!.contains("/Applications/"), "no app paths in request")
        return try response(request, object: ["status":"completed", "output":[["type":"message", "content":[["type":"output_text", "text":output]]]]])
    }
    let actual = try await AIClient(config: official, key: "dummy-test-key", transport: transport).recommendations(for: context)
    assertCheck(actual == valid, "parse and validate Responses result")
    let compatible = MockTransport { request in
        assertCheck(request.url!.path == "/v1/chat/completions", "compatible endpoint")
        return try response(request, object: ["choices":[["finish_reason":"stop", "message":["content":output]]]])
    }
    let compatibleResult = try await AIClient(config: local, key: "", transport: compatible).recommendations(for: context)
    assertCheck(compatibleResult == valid, "parse compatible result")
    let keepAlive = MockTransport { request in
        let (data, http) = try response(request, object: ["choices":[["finish_reason":"stop", "message":["content":output]]]])
        return (Data("\n\n".utf8) + data, http)
    }
    let keepAliveResult = try await AIClient(config: local, key: "", transport: keepAlive).recommendations(for: context)
    assertCheck(keepAliveResult == valid, "parse non-streaming keep-alive whitespace")
    let fenced = MockTransport { request in
        try response(request, object: ["choices":[["finish_reason":"stop", "message":["content":"```json\n\(output)\n```"]]]])
    }
    let fencedResult = try await AIClient(config: local, key: "", transport: fenced).recommendations(for: context)
    assertCheck(fencedResult == valid, "parse fenced JSON from compatible providers")
    let arrayContent = MockTransport { request in
        try response(request, object: ["choices":[["finish_reason":"stop", "message":["content":[["type":"text", "text":"{\"recommendations\":[]}"]]]]]])
    }
    let arrayResult = try await AIClient(config: local, key: "", transport: arrayContent).recommendations(for: context)
    assertCheck(arrayResult.recommendations.isEmpty && arrayResult.notes.isEmpty, "parse text content arrays and optional notes")
    let objectContent = MockTransport { request in
        try response(request, object: ["choices":[["finish_reason":"stop", "message":["content":["recommendations":[]]]]]])
    }
    let objectResult = try await AIClient(config: local, key: "", transport: objectContent).recommendations(for: context)
    assertCheck(objectResult.recommendations.isEmpty, "parse object content from compatible providers")
    let models = MockTransport { request in
        assertCheck(request.httpMethod == "GET" && request.url!.path == "/v1/models", "list models request")
        assertCheck(request.httpBody == nil, "model listing includes no file context")
        return try response(request, object: ["data":[["id":"z-model"], ["id":"a-model"], ["id":"a-model"]]])
    }
    let modelList = try await AIClient(config: local, key: "", transport: models).listModels()
    assertCheck(modelList == ["a-model", "z-model"], "deduplicate and sort models")
    let invalid = MockTransport { request in
        let bad = "{\"recommendations\":[{\"extension\":\"vue\",\"candidate_id\":\"evil.app\",\"reason\":\"x\"}],\"notes\":[]}"
        return try response(request, object: ["choices":[["finish_reason":"stop", "message":["content":bad]]]])
    }
    do { _ = try await AIClient(config: local, key: "", transport: invalid).recommendations(for: context); throw AIError.invalidContext }
    catch AIError.invalidResult { }
    catch { fputs("FAIL: invalid provider result was not rejected\n", stderr); exit(1) }
    let denied = MockTransport { request in try response(request, status: 401, object: [:]) }
    do { _ = try await AIClient(config: local, key: "", transport: denied).listModels(); throw AIError.invalidContext }
    catch AIError.unauthorized { }
    catch { fputs("FAIL: authorization failure handling\n", stderr); exit(1) }
    for (code, expected) in [(429, "rate"), (302, "redirect")] {
        let transport = MockTransport { request in try response(request, status: code, object: [:]) }
        do { _ = try await AIClient(config: local, key: "", transport: transport).listModels(); throw AIError.invalidContext }
        catch AIError.rateLimited where expected == "rate" { }
        catch AIError.service(let status) where expected == "redirect" && status == 302 { }
        catch { fputs("FAIL: HTTP status handling\n", stderr); exit(1) }
    }
    let truncated = MockTransport { request in try response(request, object: ["choices":[["finish_reason":"length", "message":["content":output]]]]) }
    do { _ = try await AIClient(config: local, key: "", transport: truncated).recommendations(for: context); throw AIError.invalidContext }
    catch AIError.responseProblem(.truncated) { }
    catch { fputs("FAIL: incomplete response handling\n", stderr); exit(1) }
    for (body, expected) in [
        (["choices":[["finish_reason":"stop", "message":["content":"   "]]]] as [String: Any], "empty"),
        (["choices":[["finish_reason":"stop", "message":["content":"not json"]]]] as [String: Any], "json"),
        (["error":["message":"dummy-private-response-secret"]] as [String: Any], "server"),
        (["unexpected":"dummy-private-response-secret"] as [String: Any], "envelope")
    ] {
        let broken = MockTransport { request in try response(request, object: body) }
        do { _ = try await AIClient(config: local, key: "", transport: broken).recommendations(for: context); throw AIError.invalidContext }
        catch AIError.responseProblem(let problem) {
            switch (problem, expected) {
            case (.emptyContent, "empty"), (.invalidJSON, "json"), (.serverError, "server"), (.envelope, "envelope"): break
            default: fputs("FAIL: classified response failure\n", stderr); exit(1)
            }
            assertCheck(!AIError.responseProblem(problem).localizedDescription.contains("dummy-private-response-secret"), "diagnostics exclude raw server content")
        }
    }
    var requestCount = 0
    var progressEvents: [Int] = []
    let manyTypes = (0..<45).map { AIFileType(fileExtension: "type\($0)", current: nil, candidates: [AICandidate(id: "selected_app", name: "Editor", registered: $0 % 2 == 0)]) }
    let batchContext = AIRequestContext(preference: "Recommend formats for Editor", types: manyTypes)
    let batched = MockTransport { request in
        requestCount += 1
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        let sent = try JSONDecoder().decode(AIRequestContext.self, from: Data(messages[1]["content"]!.utf8))
        assertCheck(sent.types.count <= 20, "each batch respects provider limit")
        let suggestions = sent.types.map { AIRecommendation(fileExtension: $0.fileExtension, candidateID: "selected_app", reason: "Example") }
        let text = String(data: try JSONEncoder().encode(AIResult(recommendations: suggestions, notes: [])), encoding: .utf8)!
        return try response(request, object: ["choices":[["finish_reason":"stop", "message":["content":text]]]])
    }
    let batchedResult = try await AIClient(config: local, key: "", transport: batched).recommendationsBatched(for: batchContext) { current, _ in progressEvents.append(current) }
    assertCheck(requestCount == 3 && progressEvents == [1, 2, 3], "batch count and progress")
    assertCheck(batchedResult.recommendations.count == 45, "merge validated batch results")
    var failingRequests = 0
    let failingBatch = MockTransport { request in
        failingRequests += 1
        if failingRequests == 2 { return try response(request, status: 401, object: [:]) }
        return try response(request, object: ["choices":[["finish_reason":"stop", "message":["content":"{\"recommendations\":[],\"notes\":[]}"]]]])
    }
    do { _ = try await AIClient(config: local, key: "", transport: failingBatch).recommendationsBatched(for: batchContext); throw AIError.invalidContext }
    catch AIError.unauthorized { }
    catch { fputs("FAIL: batch failure handling\n", stderr); exit(1) }
    assertCheck(failingRequests == 2, "failed batch stops further calls")
    print("AI provider and validation checks passed")
}
