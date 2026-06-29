import SwiftUI

// MARK: - Dashboard Screen

struct DashboardScreen: View {
    @State private var vm = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                GatewayTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(4)) {
                        headerSection
                        healthCard
                        statsGrid(stats: vm.gateStats)
                        trafficSection
                        liveFeedSection
                    }
                    .padding(.horizontal, GatewayTheme.spacing(4))
                    .padding(.top, GatewayTheme.spacing(6))
                    .padding(.bottom, GatewayTheme.spacing(12))
                }
                .scrollIndicators(.hidden)
                .refreshable { await vm.load() }

                // Top glow
                LinearGradient(
                    colors: [GatewayTheme.accentGlow, Color.clear],
                    startPoint: UnitPoint(x: 0.1, y: 0),
                    endPoint: UnitPoint(x: 0.9, y: 0.5)
                )
                .frame(height: 300)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
            .task { await vm.load() }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EDGE GATEWAY")
                .eyebrowStyle()
            (Text("Gateway status &\n")
                .foregroundStyle(GatewayTheme.text)
                + Text("live traffic")
                .foregroundStyle(GatewayTheme.accent))
                .font(.system(size: 32, weight: .heavy, design: .default))
                .tracking(-1)
                .lineSpacing(4)
        }
    }

    // MARK: Health Card

    private var healthCard: some View {
        VStack(spacing: GatewayTheme.spacing(3)) {
            HStack {
                HStack(spacing: GatewayTheme.spacing(3)) {
                    PulseDotView(color: vm.gatewayStatus.color, isActive: vm.healthResult != nil)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.gatewayStatus.label)
                            .font(.system(size: 16, weight: .heavy, design: .monospaced))
                            .foregroundStyle(vm.gatewayStatus.color)
                            .kerning(1)
                        Text("gateway · /health")
                            .monoFont(size: 11)
                            .foregroundStyle(GatewayTheme.textFaint)
                    }
                }
                Spacer()
                Button {
                    Task { await vm.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15))
                        .foregroundStyle(GatewayTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(GatewayTheme.surfaceAlt)
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                        .overlay(
                            RoundedRectangle(cornerRadius: GatewayTheme.radiusSm)
                                .stroke(GatewayTheme.border, lineWidth: 1)
                        )
                }
                .disabled(vm.isRefreshing)
                .accessibilityLabel("Refresh dashboard")
            }

            if let err = vm.healthError {
                OfflineCardView(message: err) { Task { await vm.fetchHealth() } }
            } else {
                NavigationLink(value: "items") {
                    HStack(spacing: GatewayTheme.spacing(2)) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(GatewayTheme.ok)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(GatewayTheme.accent)
                        Text("\(vm.healthResult?.itemCount ?? 0) items stored · manage →")
                            .font(.system(size: 12))
                            .foregroundStyle(GatewayTheme.textDim)
                    }
                }
            }
        }
        .padding(GatewayTheme.spacing(4))
        .cardDepth()
    }

    // MARK: Stats Grid

    private func statsGrid(stats: [(icon: String, label: String, value: String, accent: Color)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: GatewayTheme.spacing(2)) {
            ForEach(stats.indices, id: \.self) { i in
                let stat = stats[i]
                StatCardView(icon: stat.icon, label: stat.label, value: stat.value, accent: stat.accent)
            }
        }
    }

    // MARK: Traffic Section

    private var trafficSection: some View {
        VStack(spacing: GatewayTheme.spacing(3)) {
            HStack(spacing: GatewayTheme.spacing(2)) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(GatewayTheme.accent)
                Text("TRAFFIC")
                    .sectionTitleStyle()
                Spacer()
                if vm.isTrafficLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(GatewayTheme.accent)
                }
            }
            statsGrid(stats: vm.trafficStats)
        }
    }

    // MARK: Live Feed

    private var liveFeedSection: some View {
        VStack(spacing: GatewayTheme.spacing(3)) {
            HStack(spacing: GatewayTheme.spacing(2)) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(GatewayTheme.ok)
                Text("LIVE FEED")
                    .sectionTitleStyle()
                Spacer()
                PulseDotView(color: GatewayTheme.ok, isActive: true, size: 8)
            }

            if let err = vm.trafficError {
                OfflineCardView(message: err) { Task { await vm.fetchTraffic() } }
            } else if vm.trafficEntries.isEmpty {
                VStack(spacing: GatewayTheme.spacing(3)) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22))
                        .foregroundStyle(GatewayTheme.textFaint)
                    Text("No requests yet. Traffic will appear here in real time.")
                        .font(.system(size: 14))
                        .foregroundStyle(GatewayTheme.textDim)
                        .multilineTextAlignment(.center)
                }
                .padding(GatewayTheme.spacing(6))
                .frame(maxWidth: .infinity)
                .cardSurface()
            } else {
                let visible = Array(vm.trafficEntries.prefix(15))
                VStack(spacing: 0) {
                    ForEach(visible) { entry in
                        TrafficRowView(entry: entry)
                        if entry.id != visible.last?.id {
                            Divider().background(GatewayTheme.border)
                        }
                    }
                }
                .cardSurface()
            }
        }
    }
}

// MARK: - Traffic Row

private struct TrafficRowView: View {
    let entry: TrafficEntry

    var body: some View {
        HStack(spacing: GatewayTheme.spacing(3)) {
            Text(entry.method)
                .monoFont(size: 10, weight: .heavy)
                .kerning(0.5)
                .foregroundStyle(GatewayTheme.methodColor(entry.method))
                .frame(minWidth: 52)
                .padding(.vertical, 2)
                .padding(.horizontal, GatewayTheme.spacing(2))
                .background(
                    RoundedRectangle(cornerRadius: GatewayTheme.radiusSm)
                        .stroke(GatewayTheme.methodColor(entry.method), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.path)
                    .monoFont(size: 13)
                    .foregroundStyle(GatewayTheme.text)
                    .lineLimit(1)
                HStack(spacing: GatewayTheme.spacing(1)) {
                    Text("\(entry.status)")
                        .monoFont(size: 11, weight: .bold)
                        .foregroundStyle(GatewayTheme.statusColor(entry.status))
                    Text("·").foregroundStyle(GatewayTheme.textFaint)
                    Text("\(entry.latencyMs)ms")
                        .monoFont(size: 11)
                        .foregroundStyle(GatewayTheme.textFaint)
                    if !entry.cache.isEmpty, entry.cache != "MISS" {
                        Text("·").foregroundStyle(GatewayTheme.textFaint)
                        Text(entry.cache)
                            .monoFont(size: 11, weight: .bold)
                            .foregroundStyle(entry.cache == "HIT" ? GatewayTheme.accent : GatewayTheme.textFaint)
                    }
                }
            }

            Spacer()

            Text(GatewayTheme.ago(entry.ts))
                .monoFont(size: 10)
                .foregroundStyle(GatewayTheme.textFaint)
        }
        .padding(.vertical, GatewayTheme.spacing(2.5))
        .padding(.horizontal, GatewayTheme.spacing(3))
    }
}

// MARK: - Stat Card

struct StatCardView: View {
    let icon: String
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(1.5)) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(accent)
            Text(value)
                .monoFont(size: 20, weight: .heavy)
                .foregroundStyle(GatewayTheme.text)
            Text(label)
                .monoFont(size: 11)
                .foregroundStyle(GatewayTheme.textFaint)
                .kerning(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GatewayTheme.spacing(3.5))
        .background(GatewayTheme.bgElevated)
        .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
                .stroke(GatewayTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Pulse Dot

struct PulseDotView: View {
    let color: Color
    let isActive: Bool
    var size: CGFloat = 10

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(pulse ? 1.5 : 1.0)
            .opacity(pulse ? 0.4 : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default,
                value: pulse
            )
            .onAppear {
                if isActive { pulse = true }
            }
    }
}

// MARK: - Offline Card

struct OfflineCardView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: GatewayTheme.spacing(3)) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 20))
                .foregroundStyle(GatewayTheme.danger)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(GatewayTheme.textDim)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            Button(action: onRetry) {
                Text("Retry")
                    .monoFont(size: 12, weight: .bold)
                    .foregroundStyle(GatewayTheme.bg)
                    .padding(.horizontal, GatewayTheme.spacing(4))
                    .padding(.vertical, GatewayTheme.spacing(2))
                    .background(GatewayTheme.danger)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
            }
            .accessibilityLabel("Retry connection")
        }
        .padding(GatewayTheme.spacing(4))
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
                .fill(GatewayTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
                        .stroke(GatewayTheme.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var accent: Color = GatewayTheme.accent

    var body: some View {
        VStack(spacing: GatewayTheme.spacing(3)) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(accent)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GatewayTheme.text)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(GatewayTheme.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(GatewayTheme.spacing(6))
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

// MARK: - Skeleton Card

struct SkeletonCardView: View {
    var height: CGFloat = 100

    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
            .fill(GatewayTheme.surfaceAlt)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, GatewayTheme.border.opacity(0.3), Color.clear],
                            startPoint: UnitPoint(x: phase, y: 0.5),
                            endPoint: UnitPoint(x: phase + 0.5, y: 0.5)
                        )
                    )
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}
