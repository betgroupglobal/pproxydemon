import Foundation

// MARK: - AI Service Error

nonisolated enum AIServiceError: LocalizedError {
    case missingConfig
    case networkError(String)
    case httpError(Int, String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .missingConfig: return "AI service is not configured. Check your environment."
        case .networkError(let msg): return msg
        case .httpError(let code, let msg): return msg.isEmpty ? "AI request failed (\(code))" : msg
        case .noContent: return "AI returned an empty response. Try rephrasing your prompt."
        }
    }
}

// MARK: - AI Service

/// Sends chat completion requests to Kimi K2.7 Code HighSpeed via the Rork proxy.
/// Supports both one-shot and streaming (SSE) modes.
final class AIService: Sendable {
    static let shared = AIService()

    private let model = "moonshotai/kimi-k2.7-code-highspeed"
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 120
        session = URLSession(configuration: cfg)
    }

    // MARK: - URL construction

    private func buildURL() throws -> URL {
        let base = Config.EXPO_PUBLIC_TOOLKIT_URL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { throw AIServiceError.missingConfig }
        guard let url = URL(string: "\(base)/v2/vercel/v1/chat/completions") else {
            throw AIServiceError.missingConfig
        }
        return url
    }

    private var authHeader: String {
        "Bearer \(Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY)"
    }

    // MARK: - One-shot completion

    /// Single-turn chat completion — sends messages and returns the full response.
    func chat(
        systemPrompt: String,
        userMessage: String,
        temperature: Double = 0.3
    ) async throws -> String {
        let url = try buildURL()
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": 4096
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Unexpected response type.")
        }

        if http.statusCode != 200 {
            let text = String(data: data, encoding: .utf8) ?? ""
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw AIServiceError.httpError(http.statusCode, msg ?? text.prefix(200).description)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            throw AIServiceError.noContent
        }

        return content
    }

    // MARK: - Streaming completion

    /// Streaming chat completion — tokens arrive one-by-one via SSE.
    /// Returns an `AsyncThrowingStream` of content deltas.
    func chatStream(
        systemPrompt: String,
        userMessage: String,
        temperature: Double = 0.3
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.performStream(
                        systemPrompt: systemPrompt,
                        userMessage: userMessage,
                        temperature: temperature,
                        onDelta: { continuation.yield($0) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performStream(
        systemPrompt: String,
        userMessage: String,
        temperature: Double,
        onDelta: @escaping (String) -> Void
    ) async throws {
        let url = try buildURL()
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": 4096,
            "stream": true
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.networkError("Unexpected response type.")
        }
        guard http.statusCode == 200 else {
            // Drain remaining bytes for the error body
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line + "\n"
                if errorBody.count > 500 { break }
            }
            throw AIServiceError.httpError(http.statusCode, errorBody.prefix(300).description)
        }

        // Parse SSE line-by-line
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data: ") else { continue }
            let json = String(trimmed.dropFirst(6))
            guard !json.isEmpty, json != "[DONE]" else { continue }
            guard let jsonData = json.data(using: .utf8) else { continue }

            if let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let choices = obj["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                onDelta(content)
            }
        }
    }
}
