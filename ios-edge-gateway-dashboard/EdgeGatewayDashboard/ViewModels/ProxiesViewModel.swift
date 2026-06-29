import SwiftUI
import Observation

// MARK: - Proxies ViewModel

@MainActor
@Observable
final class ProxiesViewModel {
    private let api = GatewayAPIService.shared

    var proxies: [Proxy] = []
    var isLoading = false
    var isRefreshing = false
    var error: String?

    // Create form
    var targetUrl = ""
    var proxyName = ""
    var formError: String?
    var isCreating = false

    // Server launch form
    var svrTarget = ""
    var svrName = ""
    var svrPort = "12000"
    var svrConfig: String?
    var svrError: String?
    var isLaunching = false
    var isConfiguring = false
    var isStopping = false

    var servers: [ProxyServerInstance] = []
    var serversLoading = false
    var svrLoadError: String?
    var showLogsFor: Int?
    var logsText: String?

    var activeCount: Int { proxies.lazy.filter(\.enabled).count }

    var runningServerCount: Int { servers.lazy.filter { $0.status == "running" }.count }

    func load() async {
        isLoading = true
        error = nil
        do {
            proxies = try await api.fetchProxies()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refresh() async {
        isRefreshing = true
        await load()
        await fetchServers()
        isRefreshing = false
    }

    func createProxy() async {
        let trimmed = targetUrl.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            formError = "Enter a target domain."
            return
        }
        let normalized = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        formError = nil
        isCreating = true
        do {
            _ = try await api.createProxy(name: proxyName.trimmingCharacters(in: .whitespaces), targetUrl: normalized)
            targetUrl = ""
            proxyName = ""
            await load()
        } catch {
            formError = error.localizedDescription
        }
        isCreating = false
    }

    func deleteProxy(_ id: Int) async {
        do {
            try await api.deleteProxy(id: id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateProxy(id: Int, name: String? = nil, targetUrl: String? = nil,
                     enabled: Bool? = nil, interceptEnabled: Bool? = nil,
                     injectJs: String? = nil, injectJsEnabled: Bool? = nil) async {
        do {
            _ = try await api.updateProxy(id: id, name: name, targetUrl: targetUrl,
                                           enabled: enabled, interceptEnabled: interceptEnabled,
                                           injectJs: injectJs, injectJsEnabled: injectJsEnabled)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Toggle intercept on a proxy — called from the view layer.
    func toggleIntercept(for proxyId: Int, to enabled: Bool) async {
        do {
            _ = try await api.updateProxy(id: proxyId, interceptEnabled: enabled)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Servers

    func fetchServers() async {
        serversLoading = true
        svrLoadError = nil
        do {
            let result = try await api.fetchServers()
            servers = result.data
        } catch {
            svrLoadError = error.localizedDescription
        }
        serversLoading = false
    }

    func launchServer() async {
        let portNum = Int(svrPort) ?? 0
        guard portNum >= 1000 else {
            svrError = "Enter a valid port (≥1000)."
            return
        }
        guard !svrTarget.trimmingCharacters(in: .whitespaces).isEmpty else {
            svrError = "Enter a target host."
            return
        }
        svrError = nil
        isLaunching = true
        let tunnels: [ServerTunnelDef] = [ServerTunnelDef(
            name: svrTarget.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression).prefix(30).description,
            type: "http", localIP: nil, localPort: 8787, remotePort: portNum + 100, autoStart: nil
        )]
        let input = ServerLaunchInput(
            name: svrName.trimmingCharacters(in: .whitespaces).isEmpty ? "proxy-server-\(svrTarget.prefix(20))" : svrName.trimmingCharacters(in: .whitespaces),
            port: portNum, config: svrConfig, tunnels: tunnels
        )
        do {
            _ = try await api.launchServer(input)
            svrName = ""
            svrTarget = ""
            svrConfig = nil
            await fetchServers()
        } catch {
            svrError = error.localizedDescription
        }
        isLaunching = false
    }

    func configureServer() async {
        guard !svrTarget.trimmingCharacters(in: .whitespaces).isEmpty else {
            svrError = "Enter a target host first."
            return
        }
        svrError = nil
        isConfiguring = true
        do {
            let result = try await api.configureServer(targetHost: svrTarget.trimmingCharacters(in: .whitespaces),
                                                        ports: [Int(svrPort) ?? 12000], tunnelCount: 1)
            svrConfig = result.config
        } catch {
            svrError = error.localizedDescription
        }
        isConfiguring = false
    }

    func stopServer(_ id: Int) async {
        isStopping = true
        do {
            _ = try await api.stopServer(id: id)
            await fetchServers()
        } catch {
            self.error = error.localizedDescription
        }
        isStopping = false
    }

    func fetchLogs(for id: Int) async {
        if showLogsFor == id {
            showLogsFor = nil
            logsText = nil
            return
        }
        do {
            logsText = try await api.fetchServerLogs(id: id)
            showLogsFor = id
        } catch {
            self.error = error.localizedDescription
        }
    }
}
