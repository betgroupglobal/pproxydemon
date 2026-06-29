import SwiftUI
import Observation

// MARK: - Intercept Analysis ViewModel

/// Powers the "Intercept Intelligence" feature — sends captured HTTP traffic
/// to Kimi K2.7 for security analysis and presents streaming results.
@MainActor
@Observable
final class InterceptAnalysisViewModel {
    private let ai = AIService.shared
    private let api = GatewayAPIService.shared

    var isAnalyzing = false
    var analysisResult = ""
    var analysisError: String?
    var selectedCaptureIDs: Set<Int> = []

    /// Analyze all currently intercepted captures as a batch.
    func analyzeAll(captures: [InterceptCapture]) async {
        guard !captures.isEmpty else {
            analysisError = "No captured traffic to analyze."
            return
        }
        isAnalyzing = true
        analysisResult = ""
        analysisError = nil

        let payload = formatCapturePayload(captures)
        let systemPrompt = """
        You are an intercept traffic analyst for the Edge Gateway Dashboard. \
        Analyze the provided HTTP request/response captures and produce a concise \
        security and behaviour report. Focus on:

        1. **Auth & Credentials** — any tokens, cookies, or credentials observed. \
        Flag weak or missing auth patterns.
        2. **Sensitive Data Exposure** — PII, passwords, secrets in request/response bodies.
        3. **Security Headers** — missing or misconfigured CSP, HSTS, CORS, etc.
        4. **Anomalous Behaviour** — unusual status codes, large payloads, redirect chains.
        5. **Recommendations** — actionable fixes ranked by severity.

        Format your response in clear sections with emoji markers. Keep it scannable.
        Use monospace for code/header values. End with a 1-line overall risk assessment.
        """

        do {
            for try await delta in ai.chatStream(
                systemPrompt: systemPrompt,
                userMessage: payload,
                temperature: 0.2
            ) {
                analysisResult += delta
            }
        } catch {
            analysisError = error.localizedDescription
        }
        isAnalyzing = false
    }

    /// Analyze a single capture in detail.
    func analyzeSingle(_ capture: InterceptCapture) async {
        isAnalyzing = true
        analysisResult = ""
        analysisError = nil

        let payload = """
        SINGLE CAPTURE DEEP-DIVE — Proxy slug: \(capture.slug)

        REQUEST:
        \(capture.method) \(capture.path) HTTP/1.1
        Host: \(capture.host)
        Headers: \(capture.reqHeaders)
        Body: \(capture.reqBody.prefix(3000))

        RESPONSE:
        Status: \(capture.respStatus)
        Headers: \(capture.respHeaders)
        Body: \(capture.respBody.prefix(3000))
        """

        let systemPrompt = """
        Deep-analyze this single HTTP request/response pair. Identify:
        1. What kind of request this is (API call, page load, asset, AJAX)
        2. Any credentials, tokens, or session data present
        3. Response data structure and potential sensitive fields
        4. Security issues or misconfigurations
        5. Whether this looks like a login/submit endpoint

        Be concise but thorough. Use markdown formatting.
        """

        do {
            for try await delta in ai.chatStream(
                systemPrompt: systemPrompt,
                userMessage: payload,
                temperature: 0.1
            ) {
                analysisResult += delta
            }
        } catch {
            analysisError = error.localizedDescription
        }
        isAnalyzing = false
    }

    /// Build a compact but informative text representation of all captures.
    private func formatCapturePayload(_ captures: [InterceptCapture]) -> String {
        var lines: [String] = ["ANALYZE THESE \(captures.count) INTERCEPTED REQUESTS:\n"]
        for (i, cap) in captures.enumerated() {
            lines.append("--- Capture \(i + 1) [\(cap.slug)] ---")
            lines.append("\(cap.method) \(cap.path) → \(cap.respStatus)")
            lines.append("Host: \(cap.host)")
            if !cap.reqHeaders.isEmpty {
                lines.append("Req Headers: \(cap.reqHeaders.prefix(500))")
            }
            if !cap.reqBody.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("Req Body: \(cap.reqBody.prefix(1000))")
            }
            if !cap.respHeaders.isEmpty {
                lines.append("Resp Headers: \(cap.respHeaders.prefix(500))")
            }
            if !cap.respBody.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("Resp Body: \(cap.respBody.prefix(1000))")
            }
            if lines.last?.count ?? 0 > 4000 {
                lines[lines.count - 1] += "\n[...truncated for token budget...]"
                break
            }
        }
        return lines.joined(separator: "\n")
    }
}
