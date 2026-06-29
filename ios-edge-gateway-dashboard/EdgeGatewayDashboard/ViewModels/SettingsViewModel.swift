import SwiftUI
import Observation

// MARK: - Settings ViewModel

@MainActor
@Observable
final class SettingsViewModel {
    private let api = GatewayAPIService.shared

    // App settings
    var gatewayUrl = ""
    var proxyHost = ""
    var allowedOrigins = ""
    var apiKeyInput = ""
    var showApiKey = false
    var appDirty = false

    // Runtime config
    var runtimeConfig: RuntimeConfig = [:]
    var configIsLoading = false
    var configError: String?
    var configEditDirty = false
    var configOverrides: [String: String] = [:]
    var isSavingConfig = false
    var isClearingConfig = false

    // Test connection
    var isTesting = false
    var testResult: (success: Bool, message: String)?

    // Tunnels
    var tunnels: [ProxyTunnel] = []
    var tunnelsLoading = false
    var tunnelsError: String?
    var proxyStatus: ProxyStatus?

    func load() async {
        configIsLoading = true
        configError = nil
        do {
            runtimeConfig = try await api.fetchRuntimeConfig()
            configOverrides = runtimeConfig
        } catch {
            configError = error.localizedDescription
        }
        configIsLoading = false

        await refreshTunnels()
    }

    func saveAppSettings() async {
        await api.setConfig(
            baseURL: gatewayUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            apiKey: apiKeyInput.trimmingCharacters(in: .whitespaces)
        )
        appDirty = false
        UserDefaults.standard.set(gatewayUrl, forKey: "gateway_url")
        UserDefaults.standard.set(proxyHost, forKey: "proxy_host")
        UserDefaults.standard.set(allowedOrigins, forKey: "allowed_origins")
        UserDefaults.standard.set(apiKeyInput, forKey: "api_key")
    }

    func loadAppSettings() async {
        gatewayUrl = UserDefaults.standard.string(forKey: "gateway_url") ?? ""
        proxyHost = UserDefaults.standard.string(forKey: "proxy_host") ?? ""
        allowedOrigins = UserDefaults.standard.string(forKey: "allowed_origins") ?? ""
        apiKeyInput = UserDefaults.standard.string(forKey: "api_key") ?? ""
        await api.setConfig(
            baseURL: gatewayUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            apiKey: apiKeyInput.trimmingCharacters(in: .whitespaces)
        )
    }

    func updateConfigField(_ key: String, value: String) {
        configOverrides[key] = value
        configEditDirty = true
    }

    func saveRuntimeConfig() async {
        isSavingConfig = true
        do {
            runtimeConfig = try await api.updateRuntimeConfig(configOverrides)
            configEditDirty = false
        } catch {
            configError = error.localizedDescription
        }
        isSavingConfig = false
    }

    func clearRuntimeConfig() async {
        isClearingConfig = true
        do {
            runtimeConfig = try await api.deleteRuntimeConfig()
            configOverrides = runtimeConfig
            configEditDirty = false
        } catch {
            configError = error.localizedDescription
        }
        isClearingConfig = false
    }

    func testConnection() async {
        isTesting = true
        testResult = nil
        do {
            let health = try await api.fetchHealth()
            let latency = health.meta.latencyMs != 0 ? "\(health.meta.latencyMs)ms" : "?"
            let uptime = health.uptime > 0 ? ", uptime \(health.uptime / 60)m" : ""
            testResult = (true, "Gateway healthy — \(latency) latency\(uptime)")
        } catch {
            testResult = (false, error.localizedDescription)
        }
        isTesting = false
    }

    func refreshTunnels() async {
        tunnelsLoading = true
        tunnelsError = nil
        do {
            let result = try await api.fetchTunnels()
            tunnels = result.data
            proxyStatus = try? await api.fetchProxyStatus()
        } catch {
            tunnelsError = error.localizedDescription
        }
        tunnelsLoading = false
    }

    // MARK: - Config groups

    static let configGroups: [(title: String, icon: String, keys: [String])] = [
        ("Security", "shield.fill", ["API_KEY"]),
        ("Edge Proxy", "network", ["PROXY_TARGET", "BASE_DOMAIN", "ALLOWED_ORIGINS"]),
        ("Intercept Lab", "slider.horizontal.3", ["INTERCEPT_LAB_MODE", "INTERCEPT_ALLOWLIST", "INTERCEPT_BLOCKLIST", "INTERCEPT_TTL_SECONDS"]),
        ("AI Phishlet Engine", "cpu.fill", ["TOOLKIT_URL", "TOOLKIT_SECRET"]),
    ]

    static let fieldLabels: [String: String] = [
        "ALLOWED_ORIGINS": "Allowed Origins",
        "INTERCEPT_LAB_MODE": "Intercept Lab Mode",
        "INTERCEPT_ALLOWLIST": "Intercept Allowlist",
        "INTERCEPT_BLOCKLIST": "Intercept Blocklist",
        "INTERCEPT_TTL_SECONDS": "Intercept TTL",
        "API_KEY": "API Key",
        "TOOLKIT_URL": "Toolkit URL",
        "TOOLKIT_SECRET": "Toolkit Secret",
        "PROXY_TARGET": "Default Proxy Target",
        "BASE_DOMAIN": "Base Domain",
    ]

    static let fieldDefaults: [String: String] = [
        "ALLOWED_ORIGINS": "",
        "INTERCEPT_LAB_MODE": "false",
        "INTERCEPT_ALLOWLIST": "",
        "INTERCEPT_BLOCKLIST": "",
        "INTERCEPT_TTL_SECONDS": "600",
        "API_KEY": "",
        "TOOLKIT_URL": "",
        "TOOLKIT_SECRET": "",
        "PROXY_TARGET": "",
        "BASE_DOMAIN": "",
    ]

    static let fieldHints: [String: String] = [
        "ALLOWED_ORIGINS": "Comma-separated origins allowed for CORS. Use * to allow all.",
        "INTERCEPT_LAB_MODE": "Enable payload capture on proxied requests.",
        "INTERCEPT_TTL_SECONDS": "How long to retain captures (seconds). Default: 600.",
        "API_KEY": "Bearer token for write operations and config changes.",
        "TOOLKIT_SECRET": "Rork Toolkit secret for AI-powered phishlet generation.",
    ]
}
