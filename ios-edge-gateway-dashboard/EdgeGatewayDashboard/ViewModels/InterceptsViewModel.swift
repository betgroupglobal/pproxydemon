import SwiftUI
import Observation

// MARK: - Intercepts ViewModel

@MainActor
@Observable
final class InterceptsViewModel {
    private let api = GatewayAPIService.shared

    var captures: [InterceptCapture] = [] {
        didSet { _groupedCaptures = nil }
    }
    var isLoading = false
    var isRefreshing = false
    var error: String?
    var lastUpdated: Date?

    var isDeleting = false
    var isExportingHAR = false
    var isReplaying = false

    // Replay modal
    var showReplay = false
    var harPaste = ""
    var replaySlug = ""
    var replayResult: ReplayReport?
    var replayError: String?

    // Cached grouped captures — invalidated on captures change
    private var _groupedCaptures: [(slug: String, captures: [InterceptCapture])]?
    var groupedCaptures: [(slug: String, captures: [InterceptCapture])] {
        if let cached = _groupedCaptures { return cached }
        let grouped = Dictionary(grouping: captures, by: { $0.slug })
        let result = grouped.map { ($0.key, $0.value) }
            .sorted { a, b in
                let maxA = a.1.map(\.ts).max() ?? 0
                let maxB = b.1.map(\.ts).max() ?? 0
                return maxA > maxB
            }
        _groupedCaptures = result
        return result
    }

    var lastUpdatedStr: String? {
        guard let date = lastUpdated else { return nil }
        return GatewayTheme.timeFormatter.string(from: date)
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            captures = try await api.fetchIntercepts()
            lastUpdated = Date()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refresh() async {
        isRefreshing = true
        await load()
        isRefreshing = false
    }

    func deleteAll() async {
        isDeleting = true
        do {
            try await api.deleteIntercepts()
            captures = []
            lastUpdated = Date()
        } catch {
            self.error = error.localizedDescription
        }
        isDeleting = false
    }

    func exportHAR() async -> (harJson: String, fileName: String)? {
        isExportingHAR = true
        defer { isExportingHAR = false }
        do {
            return try await api.fetchHarExport()
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func runReplay() async {
        guard !harPaste.trimmingCharacters(in: .whitespaces).isEmpty,
              !replaySlug.trimmingCharacters(in: .whitespaces).isEmpty else {
            replayError = "Paste a HAR JSON blob and specify a target proxy slug."
            return
        }
        isReplaying = true
        replayError = nil
        replayResult = nil
        do {
            replayResult = try await api.replayHar(har: harPaste.trimmingCharacters(in: .whitespaces),
                                                    proxySlug: replaySlug.trimmingCharacters(in: .whitespaces))
        } catch {
            replayError = error.localizedDescription
        }
        isReplaying = false
    }
}
