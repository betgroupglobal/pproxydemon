import Foundation

// MARK: - API Error

nonisolated enum GatewayAPIError: LocalizedError {
    case badURL
    case networkError(String)
    case notJSON(Int, String)
    case httpError(Int, String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid gateway URL. Check your settings."
        case .networkError(let msg): return msg
        case .notJSON(let code, let snippet):
            return "Gateway returned non-JSON response (\(code)). Verify the URL is correct. Response: \"\(snippet)\""
        case .httpError(let code, let msg): return msg.isEmpty ? "Request failed (\(code))" : msg
        case .decodingError(let msg): return "Failed to parse response: \(msg)"
        }
    }
}

// MARK: - API Service

/// Thread-safe API service using an actor-isolated configuration store.
final class GatewayAPIService: Sendable {
    static let shared = GatewayAPIService()

    private actor Config {
        var baseURL = ""
        var apiKey = ""
        func set(baseURL: String, apiKey: String) {
            self.baseURL = baseURL
            self.apiKey = apiKey
        }
    }
    private let config = Config()

    /// Read current base URL (async — actor-isolated).
    var baseURL: String {
        get async { await config.baseURL }
    }
    /// Read current API key (async — actor-isolated).
    var apiKey: String {
        get async { await config.apiKey }
    }

    /// Bulk-update both config values atomically. Call from SettingsViewModel.
    func setConfig(baseURL: String, apiKey: String) async {
        await config.set(baseURL: baseURL, apiKey: apiKey)
    }

    private func resolve() async -> (base: String, key: String) {
        let b = await config.baseURL
        let k = await config.apiKey
        return (b, k)
    }

    private let session: URLSession
    private let decoder = JSONDecoder()

    private nonisolated static let urlTrimChars = CharacterSet(charactersIn: "/")
    private nonisolated static let harDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        session = URLSession(configuration: cfg)
    }

    // MARK: - Helpers

    private func url(_ path: String, base: String) throws -> URL {
        let raw = base.trimmingCharacters(in: Self.urlTrimChars)
        guard !raw.isEmpty, let u = URL(string: "\(raw)\(path)") else {
            throw GatewayAPIError.badURL
        }
        return u
    }

    private nonisolated func authHeader(key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return "Bearer \(trimmed)"
    }

    private func buildRequest(
        _ path: String,
        base: String,
        key: String,
        method: String = "GET",
        body: Data? = nil,
        extraHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        var req = URLRequest(url: try url(path, base: base))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = authHeader(key: key) {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = body
        return req
    }

    private func perform<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GatewayAPIError.networkError(
                "Network error — cannot reach the gateway. Verify the URL and that the service is online."
            )
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayAPIError.networkError("Unexpected response type.")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        var json: Any? = nil
        if !text.isEmpty {
            do {
                json = try JSONSerialization.jsonObject(with: data)
            } catch {
                let snippet = String(text.prefix(200)).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                throw GatewayAPIError.notJSON(httpResponse.statusCode, snippet + (text.count > 200 ? "…" : ""))
            }
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let msg = (json as? [String: Any])?["error"] as? String ?? ""
            throw GatewayAPIError.httpError(httpResponse.statusCode, msg)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GatewayAPIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Health

    func fetchHealth() async throws -> HealthResult {
        let (base, key) = await resolve()
        let req = try buildRequest("/health", base: base, key: key)
        return try await perform(req)
    }

    // MARK: - Items

    func fetchItems() async throws -> ItemsResult {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/items", base: base, key: key)
        let wrapper: ApiResponse<[Item]> = try await perform(req)
        return ItemsResult(
            items: wrapper.data,
            meta: GatewayMeta(latencyMs: 0, cache: nil, edgeLatency: nil, rateLimit: nil, rateRemaining: nil)
        )
    }

    func createItem(name: String, description: String) async throws -> Item {
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(["name": name, "description": description])
        let req = try buildRequest("/api/items", base: base, key: key, method: "POST", body: body)
        let wrapper: ApiResponse<Item> = try await perform(req)
        return wrapper.data
    }

    func updateItem(id: Int, name: String, description: String) async throws -> Item {
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(["name": name, "description": description])
        let req = try buildRequest("/api/items/\(id)", base: base, key: key, method: "PUT", body: body)
        let wrapper: ApiResponse<Item> = try await perform(req)
        return wrapper.data
    }

    func deleteItem(id: Int) async throws {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/items/\(id)", base: base, key: key, method: "DELETE")
        _ = try await perform(req) as ApiSuccessResponse
    }

    // MARK: - Proxies

    func fetchProxies() async throws -> [Proxy] {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxies", base: base, key: key)
        let wrapper: ApiListResponse<Proxy> = try await perform(req)
        return wrapper.data
    }

    func createProxy(name: String, targetUrl: String) async throws -> Proxy {
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(["name": name, "targetUrl": targetUrl])
        let req = try buildRequest("/api/proxies", base: base, key: key, method: "POST", body: body)
        let wrapper: ApiResponse<Proxy> = try await perform(req)
        return wrapper.data
    }

    func updateProxy(
        id: Int,
        name: String? = nil,
        targetUrl: String? = nil,
        enabled: Bool? = nil,
        interceptEnabled: Bool? = nil,
        injectJs: String? = nil,
        injectJsEnabled: Bool? = nil
    ) async throws -> Proxy {
        let (base, key) = await resolve()
        var dict: [String: Any] = [:]
        if let v = name { dict["name"] = v }
        if let v = targetUrl { dict["targetUrl"] = v }
        if let v = enabled { dict["enabled"] = v }
        if let v = interceptEnabled { dict["interceptEnabled"] = v }
        if let v = injectJs { dict["injectJs"] = v }
        if let v = injectJsEnabled { dict["injectJsEnabled"] = v }
        let body = try JSONSerialization.data(withJSONObject: dict)
        let req = try buildRequest("/api/proxies/\(id)", base: base, key: key, method: "PUT", body: body)
        let wrapper: ApiResponse<Proxy> = try await perform(req)
        return wrapper.data
    }

    func deleteProxy(id: Int) async throws {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxies/\(id)", base: base, key: key, method: "DELETE")
        _ = try await perform(req) as ApiSuccessResponse
    }

    func proxyURL(slug: String) async throws -> URL {
        let base = await config.baseURL
        return try url("/proxy/\(slug)", base: base)
    }

    // MARK: - Tunnels

    func fetchProxyStatus() async throws -> ProxyStatus {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxy/status", base: base, key: key)
        let wrapper: ApiResponse<ProxyStatus> = try await perform(req)
        return wrapper.data
    }

    func fetchTunnels() async throws -> TunnelListResult {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxy/tunnels", base: base, key: key)
        return try await perform(req)
    }

    func createTunnel(_ input: TunnelCreateInput) async throws -> ProxyTunnel {
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(input)
        let req = try buildRequest("/api/proxy/tunnels", base: base, key: key, method: "POST", body: body)
        let wrapper: ApiResponse<ProxyTunnel> = try await perform(req)
        return wrapper.data
    }

    func deleteTunnel(id: Int) async throws {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxy/tunnels/\(id)", base: base, key: key, method: "DELETE")
        _ = try await perform(req) as ApiSuccessResponse
    }

    func startTunnel(id: Int) async throws -> ProxyTunnel {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxy/tunnels/\(id)/start", base: base, key: key, method: "POST")
        let wrapper: ApiResponse<ProxyTunnel> = try await perform(req)
        return wrapper.data
    }

    func stopTunnel(id: Int) async throws -> ProxyTunnel {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxy/tunnels/\(id)/stop", base: base, key: key, method: "POST")
        let wrapper: ApiResponse<ProxyTunnel> = try await perform(req)
        return wrapper.data
    }

    // MARK: - Intercepts

    func fetchIntercepts() async throws -> [InterceptCapture] {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/intercepts", base: base, key: key, extraHeaders: ["X-Intercept-TTL": "600"])
        let wrapper: ApiCountResponse<InterceptCapture> = try await perform(req)
        return wrapper.data
    }

    func deleteIntercepts() async throws {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/intercepts", base: base, key: key, method: "DELETE")
        _ = try await perform(req) as ApiSuccessResponse
    }

    // MARK: - Traffic

    func fetchTraffic() async throws -> TrafficResult {
        nonisolated struct TrafficWrapper: Decodable { let data: [TrafficEntry]; let stats: TrafficStats }
        let (base, key) = await resolve()
        let req = try buildRequest("/api/traffic", base: base, key: key)
        let wrapper: TrafficWrapper = try await perform(req)
        return TrafficResult(entries: wrapper.data, stats: wrapper.stats, meta: GatewayMeta(latencyMs: 0, cache: nil, edgeLatency: nil, rateLimit: nil, rateRemaining: nil))
    }

    // MARK: - Runtime Config

    func fetchRuntimeConfig() async throws -> RuntimeConfig {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/config", base: base, key: key)
        let wrapper: ApiResponse<RuntimeConfig> = try await perform(req)
        return wrapper.data
    }

    func updateRuntimeConfig(_ entries: RuntimeConfig) async throws -> RuntimeConfig {
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(entries)
        let req = try buildRequest("/api/config", base: base, key: key, method: "PUT", body: body)
        let wrapper: ApiResponse<RuntimeConfig> = try await perform(req)
        return wrapper.data
    }

    func deleteRuntimeConfig() async throws -> RuntimeConfig {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/config", base: base, key: key, method: "DELETE")
        let wrapper: ApiResponse<RuntimeConfig> = try await perform(req)
        return wrapper.data
    }

    // MARK: - Recon

    func generatePhishlet(proxyId: Int, input: ReconInput) async throws -> ReconResult {
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(input)
        let req = try buildRequest("/api/proxies/\(proxyId)/recon", base: base, key: key, method: "POST", body: body)
        let wrapper: ApiResponse<ReconResult> = try await perform(req)
        return wrapper.data
    }

    func generateLoginPhishlet(proxyId: Int, input: LoginPhishletInput) async throws -> ReconResult {
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(input)
        let req = try buildRequest("/api/proxies/\(proxyId)/login-phishlet", base: base, key: key, method: "POST", body: body)
        let wrapper: ApiResponse<ReconResult> = try await perform(req)
        return wrapper.data
    }

    func iteratePhishlet(proxyId: Int, phishlet: String, captured: CapturedData) async throws -> IterateResult {
        struct IterateInput: Codable { let phishlet: String; let captured: CapturedData }
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(IterateInput(phishlet: phishlet, captured: captured))
        let req = try buildRequest("/api/proxies/\(proxyId)/recon/iterate", base: base, key: key, method: "POST", body: body)
        let wrapper: ApiResponse<IterateResult> = try await perform(req)
        return wrapper.data
    }

    // MARK: - HAR

    func fetchHarExport() async throws -> (harJson: String, fileName: String) {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/intercepts/har", base: base, key: key)
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayAPIError.networkError("Unexpected response type from HAR endpoint.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            var err: [String: Any] = [:]
            if let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { err = d }
            throw GatewayAPIError.httpError(httpResponse.statusCode, err["error"] as? String ?? "")
        }
        let harJson = String(data: data, encoding: .utf8) ?? ""
        let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let fileName: String
        if let range = disposition.range(of: "filename=") {
            fileName = String(disposition[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        } else {
            fileName = "edge-gateway-\(Self.harDateFormatter.string(from: Date())).har"
        }
        return (harJson, fileName)
    }

    // MARK: - Replay

    func replayHar(har: String, proxySlug: String) async throws -> ReplayReport {
        struct ReplayInput: Codable { let har: String; let proxySlug: String }
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(ReplayInput(har: har, proxySlug: proxySlug))
        let req = try buildRequest("/api/replay", base: base, key: key, method: "POST", body: body)
        let wrapper: ApiResponse<ReplayReport> = try await perform(req)
        return wrapper.data
    }

    // MARK: - Proxy Servers

    func fetchServers() async throws -> ServerListResult {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxy/servers", base: base, key: key)
        return try await perform(req)
    }

    func launchServer(_ input: ServerLaunchInput) async throws -> ProxyServerInstance {
        let (base, key) = await resolve()
        let body = try JSONEncoder().encode(input)
        let req = try buildRequest("/api/proxy/servers/launch", base: base, key: key, method: "POST", body: body)
        let wrapper: ApiResponse<ProxyServerInstance> = try await perform(req)
        return wrapper.data
    }

    func stopServer(id: Int) async throws -> Bool {
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxy/servers/\(id)/stop", base: base, key: key, method: "POST")
        let wrapper: ApiSuccessResponse = try await perform(req)
        return wrapper.success
    }

    func fetchServerLogs(id: Int) async throws -> String {
        nonisolated struct LogsWrapper: Decodable { let data: LogsData }
        nonisolated struct LogsData: Decodable { let logs: String }
        let (base, key) = await resolve()
        let req = try buildRequest("/api/proxy/servers/\(id)/logs", base: base, key: key)
        let wrapper: LogsWrapper = try await perform(req)
        return wrapper.data.logs
    }

    func configureServer(targetHost: String, ports: [Int]? = nil, tunnelCount: Int? = nil) async throws -> ServerConfigResult {
        let (base, key) = await resolve()
        var dict: [String: Any] = ["targetHost": targetHost]
        if let p = ports { dict["ports"] = p }
        if let t = tunnelCount { dict["tunnelCount"] = t }
        let body = try JSONSerialization.data(withJSONObject: dict)
        let req = try buildRequest("/api/proxy/servers/configure", base: base, key: key, method: "POST", body: body)
        let wrapper: ApiResponse<ServerConfigResult> = try await perform(req)
        return wrapper.data
    }
}
