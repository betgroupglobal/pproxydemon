import SwiftUI
import Observation

// MARK: - Proxy Config Assistant ViewModel

/// Powers the "Proxy Config Assistant" — uses Kimi K2.7 to generate,
/// explain, and validate proxy server configurations based on user intent.
@MainActor
@Observable
final class ProxyConfigAssistantViewModel {
    private let ai = AIService.shared

    var isGenerating = false
    var assistantResult = ""
    var assistantError: String?
    var userIntent = ""

    /// Generate a proxy server configuration from a natural-language description.
    func generateConfig() async {
        let trimmed = userIntent.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            assistantError = "Describe what you want the proxy to do first."
            return
        }

        isGenerating = true
        assistantResult = ""
        assistantError = nil

        let systemPrompt = """
        You are a proxy configuration expert for the Edge Gateway Dashboard. \
        The user describes what they need in plain language. You output a complete \
        proxy server configuration in TOML format suitable for the edge gateway.

        The config format supports:
        - [server] section: bind_addr, bind_port, tls settings
        - [[targets]] array: slug, target_url, intercept, inject_js, enabled
        - [[tunnels]] array: name, type (http/tcp), local_port, remote_port
        - Global settings: rate_limit, cache_ttl, log_level

        Rules:
        1. Always include a [server] section with a bind_port.
        2. Every target must have a slug (lowercase, hyphenated) and target_url.
        3. If the user mentions intercepting traffic, set intercept = true.
        4. If they mention a specific domain, make it the first target.
        5. Add helpful comments explaining each section.
        6. After the TOML config, add a "## QUICK START" section with 2-3 bullet points \
        on how to verify the proxy is working.

        Output ONLY the configuration and quick start. No preamble or sign-off.
        """

        do {
            for try await delta in ai.chatStream(
                systemPrompt: systemPrompt,
                userMessage: "I need a proxy configuration that: \(trimmed)",
                temperature: 0.3
            ) {
                assistantResult += delta
            }
        } catch {
            assistantError = error.localizedDescription
        }
        isGenerating = false
    }

    /// Explain what a given proxy configuration does in plain English.
    func explainConfig(_ config: String) async {
        let trimmed = config.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            assistantError = "Paste a config to explain."
            return
        }

        isGenerating = true
        assistantResult = ""
        assistantError = nil

        let systemPrompt = """
        You explain proxy server configurations in plain English. \
        Given a TOML proxy configuration, describe:
        1. What the proxy does overall (one sentence)
        2. Each target — what domain it routes to and any special behaviour
        3. Tunnel setup if present
        4. Any security or performance considerations
        5. One recommendation for improvement

        Be concise. Use bullet points. No preamble.
        """

        do {
            for try await delta in ai.chatStream(
                systemPrompt: systemPrompt,
                userMessage: "Explain this proxy config:\n```toml\n\(trimmed)\n```",
                temperature: 0.2
            ) {
                assistantResult += delta
            }
        } catch {
            assistantError = error.localizedDescription
        }
        isGenerating = false
    }

    /// Generate proxy routing rules for a specific use case.
    func suggestRules(for useCase: ProxyUseCase) async {
        isGenerating = true
        assistantResult = ""
        assistantError = nil

        let (systemPrompt, userPrompt) = useCasePrompts(useCase)

        do {
            for try await delta in ai.chatStream(
                systemPrompt: systemPrompt,
                userMessage: userPrompt,
                temperature: 0.3
            ) {
                assistantResult += delta
            }
        } catch {
            assistantError = error.localizedDescription
        }
        isGenerating = false
    }

    private func useCasePrompts(_ useCase: ProxyUseCase) -> (system: String, user: String) {
        let base = """
        You are a proxy routing expert. Output only the target definitions \
        and any special configuration needed. Use TOML format with comments.
        """

        switch useCase {
        case .apiGateway:
            return (base, "Create proxy targets for an API gateway that routes /api/users, /api/orders, and /api/products to separate backend microservices on different ports (3001, 3002, 3003). Include rate limiting at 100 req/s per target.")
        case .authProxy:
            return (base, "Create a proxy config that intercepts login forms on a web app at example.com, captures auth tokens from response headers, and injects a script to monitor post-login redirects. Enable full intercept mode.")
        case .cdnCacheProxy:
            return (base, "Create a caching CDN proxy for a static site at my-blog.com. Cache all assets (CSS, JS, images) for 1 hour. Bypass cache for /api/* paths. Set appropriate cache headers.")
        case .debugProxy:
            return (base, "Create a debugging proxy that logs every request/response header and body to the intercepts dashboard for a target at staging.example.com. Enable verbose logging mode. Intercept everything.")
        case .custom:
            return (base, "Generate proxy targets based on this description: \(userIntent)")
        }
    }
}

// MARK: - Proxy Use Cases

enum ProxyUseCase: String, CaseIterable, Identifiable {
    case apiGateway = "API Gateway"
    case authProxy = "Auth Interceptor"
    case cdnCacheProxy = "CDN Cache"
    case debugProxy = "Debug Proxy"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .apiGateway: return "arrow.triangle.branch"
        case .authProxy: return "lock.shield.fill"
        case .cdnCacheProxy: return "clock.arrow.2.circlepath"
        case .debugProxy: return "ant.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    var description: String {
        switch self {
        case .apiGateway: return "Route APIs to microservices"
        case .authProxy: return "Intercept login forms & tokens"
        case .cdnCacheProxy: return "Cache static assets at edge"
        case .debugProxy: return "Log every request for debugging"
        case .custom: return "Describe your own use case"
        }
    }
}
