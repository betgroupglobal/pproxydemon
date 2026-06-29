import SwiftUI
import Observation

// MARK: - Dashboard ViewModel

@MainActor
@Observable
final class DashboardViewModel {
    private let api = GatewayAPIService.shared

    var healthResult: HealthResult?
    var healthError: String?
    var isHealthLoading = false

    var trafficResult: TrafficResult?
    var trafficError: String?
    var isTrafficLoading = false

    var isRefreshing: Bool { isHealthLoading || isTrafficLoading }

    var gatewayStatus: (label: String, color: Color) {
        if healthError != nil { return ("UNREACHABLE", GatewayTheme.danger) }
        if healthResult != nil { return ("OPERATIONAL", GatewayTheme.ok) }
        return ("CONNECTING", GatewayTheme.warn)
    }

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchHealth() }
            group.addTask { await self.fetchTraffic() }
        }
    }

    func fetchHealth() async {
        isHealthLoading = true
        healthError = nil
        do {
            healthResult = try await api.fetchHealth()
        } catch {
            healthError = error.localizedDescription
        }
        isHealthLoading = false
    }

    func fetchTraffic() async {
        isTrafficLoading = true
        trafficError = nil
        do {
            trafficResult = try await api.fetchTraffic()
        } catch {
            trafficError = error.localizedDescription
        }
        isTrafficLoading = false
    }

    // MARK: - Computed (cached only when data changes via @Observable tracking)

    var gateStats: [(icon: String, label: String, value: String, accent: Color)] {
        guard let h = healthResult else {
            return [
                ("bolt.fill", "Latency", "—", GatewayTheme.accent),
                ("gauge.with.dots.needle.33percent", "Edge", "—", GatewayTheme.cyan),
                ("clock.fill", "Uptime", "—", GatewayTheme.ok),
                ("activity", "Rate", "—", GatewayTheme.warn),
            ]
        }
        let latency = h.meta.latencyMs != 0 ? "\(h.meta.latencyMs)ms" : "—"
        let edge = h.meta.edgeLatency ?? "—"
        let uptime = GatewayTheme.formatUptime(h.uptime)
        let rate: String
        if let rem = h.meta.rateRemaining, let lim = h.meta.rateLimit {
            rate = "\(rem)/\(lim)"
        } else {
            rate = "—"
        }
        return [
            ("bolt.fill", "Latency", latency, GatewayTheme.accent),
            ("gauge.with.dots.needle.33percent", "Edge", edge, GatewayTheme.cyan),
            ("clock.fill", "Uptime", uptime, GatewayTheme.ok),
            ("activity", "Rate", rate, GatewayTheme.warn),
        ]
    }

    var trafficStats: [(icon: String, label: String, value: String, accent: Color)] {
        guard let t = trafficResult else {
            return [
                ("internaldrive.fill", "Requests", "—", GatewayTheme.accent),
                ("timer", "Avg latency", "—", GatewayTheme.cyan),
                ("bolt.fill", "Cache hits", "—", GatewayTheme.ok),
                ("exclamationmark.triangle.fill", "Errors", "—", GatewayTheme.danger),
            ]
        }
        return [
            ("internaldrive.fill", "Requests", "\(t.stats.total)", GatewayTheme.accent),
            ("timer", "Avg latency", "\(t.stats.avgLatency)ms", GatewayTheme.cyan),
            ("bolt.fill", "Cache hits", "\(t.stats.cacheHits)", GatewayTheme.ok),
            ("exclamationmark.triangle.fill", "Errors", "\(t.stats.errorCount)", GatewayTheme.danger),
        ]
    }

    var trafficEntries: [TrafficEntry] {
        trafficResult?.entries ?? []
    }
}
