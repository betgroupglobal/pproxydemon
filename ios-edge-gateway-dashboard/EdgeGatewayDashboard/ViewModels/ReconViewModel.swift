import SwiftUI
import Observation

// MARK: - Recon ViewModel

enum ReconStage: String {
    case idle, scanning, generating, iterating, done

    var label: String {
        switch self {
        case .idle: return ""
        case .scanning: return "Scanning target — browse the login page…"
        case .generating: return "Generating phishlet YAML…"
        case .iterating: return "Self-critique & refining…"
        case .done: return "Scan complete"
        }
    }

    var color: Color {
        switch self {
        case .idle: return GatewayTheme.textFaint
        case .scanning: return GatewayTheme.cyan
        case .generating: return GatewayTheme.accent
        case .iterating: return GatewayTheme.warn
        case .done: return GatewayTheme.ok
        }
    }

    var icon: String {
        switch self {
        case .idle: return ""
        case .scanning: return "dot.radiowaves.left.and.right"
        case .generating: return "wand.and.stars"
        case .iterating: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        }
    }
}

@MainActor
@Observable
final class ReconViewModel {
    private let api = GatewayAPIService.shared

    var proxies: [Proxy] = []
    var proxiesError: String?
    var isLoading = false
    var error: String?

    var selectedSlug = ""
    var selectedProxy: Proxy? { proxies.first(where: { $0.slug == selectedSlug }) }

    var stage: ReconStage = .idle
    var generated = ""
    var refinedYaml = ""
    var iterateResult: IterateResult?

    // Login mode
    var loginMode = false
    var loginUrl = ""
    var loginYaml = ""
    var isGeneratingLogin = false
    var showAgentCommand = false

    var activeUrl = ""
    var capturedData: CapturedData?
    /// Pre-computed agent command so the view doesn't await the actor mid-render.
    var agentCommand = ""

    func load() async {
        isLoading = true
        error = nil
        do {
            proxies = try await api.fetchProxies()
            if proxies.count == 1, selectedSlug.isEmpty {
                selectedSlug = proxies[0].slug
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func startScan() async {
        guard let proxy = selectedProxy else { return }
        capturedData = nil
        generated = ""
        refinedYaml = ""
        iterateResult = nil
        loginMode = false
        loginYaml = ""
        stage = .scanning
        activeUrl = (try? await api.proxyURL(slug: proxy.slug).absoluteString) ?? ""
    }

    func startLoginScan() {
        guard selectedProxy != nil, !loginUrl.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let trimmed = loginUrl.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed),
              url.scheme == "http" || url.scheme == "https" else { return }
        loginMode = true
        loginYaml = ""
        capturedData = nil
        generated = ""
        refinedYaml = ""
        iterateResult = nil
        activeUrl = trimmed
    }

    func reset() {
        capturedData = nil
        generated = ""
        refinedYaml = ""
        iterateResult = nil
        stage = .idle
        activeUrl = ""
        loginMode = false
        loginUrl = ""
        loginYaml = ""
        agentCommand = ""
    }

    func generatePhishlet() async {
        guard let proxy = selectedProxy, let captured = capturedData else { return }
        stage = .generating
        do {
            let input = ReconInput(targetUrl: proxy.targetUrl, captured: captured)
            let result = try await api.generatePhishlet(proxyId: proxy.id, input: input)
            generated = result.phishlet
            await iteratePhishlet()
        } catch {
            stage = .idle
            self.error = error.localizedDescription
        }
    }

    func generateLoginPhishlet() async {
        guard let proxy = selectedProxy, let captured = capturedData else { return }
        isGeneratingLogin = true
        do {
            let form = captured
            let loginForm = LoginFormData(
                domain: form.pageTitle,
                loginPath: form.formAction,
                submitSelector: nil,
                usernameField: form.formFields?.first(where: { $0.name.lowercased().contains("user") || $0.type == "email" })?.name,
                passwordField: form.formFields?.first(where: { $0.type == "password" })?.name,
                hiddenInputs: form.hiddenInputs
            )
            let input = LoginPhishletInput(targetUrl: activeUrl.isEmpty ? loginUrl : activeUrl, loginForm: loginForm)
            let result = try await api.generateLoginPhishlet(proxyId: proxy.id, input: input)
            loginYaml = result.phishlet
        } catch {
            self.error = error.localizedDescription
        }
        isGeneratingLogin = false
    }

    private func iteratePhishlet() async {
        guard let proxy = selectedProxy, let captured = capturedData, !generated.isEmpty else { return }
        stage = .iterating
        do {
            let result = try await api.iteratePhishlet(proxyId: proxy.id, phishlet: generated, captured: captured)
            refinedYaml = result.phishlet
            iterateResult = result
            stage = .done
        } catch {
            stage = .done
            self.error = error.localizedDescription
        }
    }

    /// Build the agent command string — call this before showing it since it reads the actor config.
    func prepareAgentCommand() async {
        guard let proxy = selectedProxy, !loginUrl.trimmingCharacters(in: .whitespaces).isEmpty else {
            agentCommand = ""
            return
        }
        let trimmed = loginUrl.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed),
              url.scheme == "http" || url.scheme == "https" else {
            agentCommand = ""
            return
        }
        let base = await api.baseURL
        agentCommand = """
        GATEWAY_BASE_URL=\(base) \\
        GATEWAY_API_KEY=$GATEWAY_API_KEY \\
        PROXY_ID=\(proxy.id) \\
        npx tsx agents/phishlet-constructor.ts \\
          --target-url "\(trimmed)" \\
          --authorized
        """
    }
}
