import Foundation

// MARK: - Health

nonisolated struct HealthResult: Codable, Sendable {
    let status: String
    let timestamp: String
    let uptime: Int
    let itemCount: Int
    let region: String
    let meta: GatewayMeta
}

nonisolated struct GatewayMeta: Codable, Sendable {
    let latencyMs: Int
    let cache: String?
    let edgeLatency: String?
    let rateLimit: Int?
    let rateRemaining: Int?
}

// MARK: - Items

nonisolated struct Item: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let description: String
    let createdAt: Int
    let updatedAt: Int
}

nonisolated struct ItemsResult: Codable, Sendable {
    let items: [Item]
    let meta: GatewayMeta
}

// MARK: - Traffic

nonisolated struct TrafficEntry: Codable, Identifiable, Sendable {
    let id: Int
    let ts: Int
    let method: String
    let path: String
    let status: Int
    let latencyMs: Int
    let cache: String
    let ip: String
    let country: String
    let colo: String
    let proxy: String
}

nonisolated struct TrafficStats: Codable, Sendable {
    let total: Int
    let avgLatency: Int
    let errorCount: Int
    let cacheHits: Int
}

nonisolated struct TrafficResult: Codable, Sendable {
    let entries: [TrafficEntry]
    let stats: TrafficStats
    let meta: GatewayMeta
}

// MARK: - Proxies

nonisolated struct Proxy: Codable, Identifiable, Sendable {
    let id: Int
    let slug: String
    let name: String
    let targetUrl: String
    let enabled: Bool
    let hits: Int
    let proxyDomain: String
    let interceptEnabled: Bool
    let injectJs: String
    let injectJsEnabled: Bool
    let phishlet: String
    let tunnelId: Int?
    let createdAt: Int
    let updatedAt: Int
}

// MARK: - Tunnels

nonisolated struct ProxyTunnel: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let type: String
    let remotePort: Int
    let localHost: String
    let localPort: Int
    let status: String
    let uptime: Int
    let bytesIn: Int
    let bytesOut: Int
    let activeConns: Int
}

nonisolated struct TunnelListResult: Codable, Sendable {
    let data: [ProxyTunnel]
    let count: Int
}

nonisolated struct TunnelCreateInput: Codable, Sendable {
    let name: String
    let type: String?
    let localIP: String?
    let localPort: Int
    let remotePort: Int?
    let autoStart: Bool?

    enum CodingKeys: String, CodingKey {
        case name, type, localIP, localPort, remotePort, autoStart
    }
}

nonisolated struct ProxyStatus: Codable, Sendable {
    let status: String
    let tunnelCount: Int
    let tunnelsRunning: Int
    let tunnelsStopped: Int
    let totalBytesTransferred: Int
    let totalActiveConns: Int
    let config: ProxyStatusConfig
}

nonisolated struct ProxyStatusConfig: Codable, Sendable {
    let bindAddr: String
    let bindPort: Int
}

// MARK: - Intercepts

nonisolated struct InterceptCapture: Codable, Identifiable, Sendable {
    let id: Int
    let ts: Int
    let slug: String
    let method: String
    let path: String
    let reqHeaders: String
    let reqBody: String
    let respStatus: Int
    let respHeaders: String
    let respBody: String
    let host: String
}

// MARK: - Runtime Config

typealias RuntimeConfig = [String: String]

// MARK: - Recon / Phishlet

nonisolated struct ReconInput: Codable, Sendable {
    let targetUrl: String
    let captured: CapturedData
}

nonisolated struct CapturedData: Codable, Sendable {
    var urls: [String]?
    var cookies: [String]?
    var formFields: [CapturedFormField]?
    var redirects: [String]?
    var domains: [String]?
    var pageTitle: String?
    var formAction: String?
    var formMethod: String?
    var hiddenInputs: [CapturedHiddenInput]?
    var csrfFields: [CapturedHiddenInput]?
    var authLinks: [CapturedAuthLink]?
    var apiEndpoints: [String]?
    var scripts: [String]?
    var forms: [CapturedForm]?
}

nonisolated struct CapturedFormField: Codable, Sendable {
    let name: String
    let type: String
    let id: String?
    let placeholder: String?
    let required: Bool?
    let autocomplete: String?
}

nonisolated struct CapturedHiddenInput: Codable, Sendable {
    let name: String
    let value: String
    let id: String?
}

nonisolated struct CapturedAuthLink: Codable, Sendable {
    let href: String
    let text: String
}

nonisolated struct CapturedForm: Codable, Sendable {
    let action: String
    let method: String
    let id: String?
    let name: String?
}

nonisolated struct ReconResult: Codable, Sendable {
    let proxyId: Int
    let phishlet: String
}

nonisolated struct LoginPhishletInput: Codable, Sendable {
    let targetUrl: String
    let loginForm: LoginFormData
}

nonisolated struct LoginFormData: Codable, Sendable {
    let domain: String?
    let loginPath: String?
    let submitSelector: String?
    let usernameField: String?
    let passwordField: String?
    let hiddenInputs: [CapturedHiddenInput]?
}

nonisolated struct IterateResult: Codable, Sendable {
    let proxyId: Int
    let phishlet: String
    let passes: Int
    let critiques: [CritiqueEntry]
    let improvements: [String]
    let score: Int
}

nonisolated struct CritiqueEntry: Codable, Sendable {
    let pass: Int
    let finding: String
    let severity: String
    let fix: String
}

// MARK: - Replay

nonisolated struct ReplayReport: Codable, Sendable {
    let total: Int
    let succeeded: Int
    let failed: Int
    let entries: [ReplayEntry]
    let extractedTokens: [String]
    let flowSummary: String
}

nonisolated struct ReplayEntry: Codable, Sendable {
    let index: Int
    let method: String
    let url: String
    let status: Int
    let latencyMs: Int
    let redirectUrl: String?
    let cookies: [String]
    let credentials: [String: String]
    let error: String?
}

// MARK: - Proxy Server Instances

nonisolated struct ProxyServerInstance: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let port: Int
    let apiPort: Int
    let pid: Int
    let status: String
    let uptime: Int
    let health: ServerHealth?
    let tunnelCount: Int
    let startedAt: Int
}

nonisolated struct ServerHealth: Codable, Sendable {
    let status: String
    let uptime: Int?
}

nonisolated struct ServerListResult: Codable, Sendable {
    let data: [ProxyServerInstance]
    let count: Int
}

nonisolated struct ServerLaunchInput: Codable, Sendable {
    let name: String
    let port: Int
    let config: String?
    let tunnels: [ServerTunnelDef]?
}

nonisolated struct ServerTunnelDef: Codable, Sendable {
    let name: String
    let type: String?
    let localIP: String?
    let localPort: Int
    let remotePort: Int?
    let autoStart: Bool?
}

nonisolated struct ServerConfigResult: Codable, Sendable {
    let config: String
    let model: String?
    let generated: Bool
}

nonisolated struct ServerValidateResult: Codable, Sendable {
    let valid: Bool
    let issues: [ServerValidateIssue]
}

nonisolated struct ServerValidateIssue: Codable, Sendable {
    let severity: String
    let line: String?
    let message: String
    let fix: String?
}

// MARK: - API Wrapper types

nonisolated struct ApiResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: T
}

nonisolated struct ApiListResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: [T]
}

nonisolated struct ApiSuccessResponse: Codable, Sendable {
    let success: Bool
}

nonisolated struct ApiCountResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: [T]
    let count: Int
}
