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
    let fenced = MockTransport { request in
        try response(request, object: ["choices":[["finish_reason":"stop", "message":["content":"```json\n\(output)\n```"]]]])
    }
    let fencedResult = try await AIClient(config: local, key: "", transport: fenced).recommendations(for: context)
    assertCheck(fencedResult == valid, "parse fenced JSON from compatible providers")
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
    catch AIError.invalidResponse { }
    catch { fputs("FAIL: incomplete response handling\n", stderr); exit(1) }
    print("AI provider and validation checks passed")
}
