import SwiftUI

// MARK: - Settings Screen

struct SettingsScreen: View {
    @State private var vm = SettingsViewModel()
    @State private var showApiKey = false
    @State private var fieldValues: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                GatewayTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
                        Text("SETTINGS").eyebrowStyle()
                        Text("Configuration")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(GatewayTheme.text)
                        Text("Manage API keys, app settings, runtime configuration, proxy tunnels, and architecture reference — all from one place.")
                            .font(.system(size: 13))
                            .foregroundStyle(GatewayTheme.textDim)
                            .lineSpacing(4)

                        if vm.gatewayUrl.trimmingCharacters(in: .whitespaces).isEmpty {
                            setupBanner
                        }

                        apiKeySection
                        appSettingsSection
                        runtimeConfigSection
                        tunnelsSection
                        gatewayUrlsSection
                        architectureSection
                        capabilitiesSection

                        // Docs link
                        Link(destination: URL(string: "https://github.com/fatedier/frp") ?? URL(string: "https://github.com")!) {
                            HStack(spacing: GatewayTheme.spacing(2)) {
                                Text("frp — fast reverse proxy docs")
                                    .font(.system(size: 14, weight: .heavy))
                                Image(systemName: "arrow.right")
                            }
                            .foregroundStyle(GatewayTheme.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, GatewayTheme.spacing(3.5))
                            .background(GatewayTheme.accent)
                            .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
                        }

                        Text("Edge Gateway Dashboard · built with Rork")
                            .monoFont(size: 11)
                            .foregroundStyle(GatewayTheme.textFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, GatewayTheme.spacing(4))
                    }
                    .padding(.horizontal, GatewayTheme.spacing(4))
                    .padding(.top, GatewayTheme.spacing(6))
                    .padding(.bottom, GatewayTheme.spacing(12))
                }
                .scrollIndicators(.hidden)

                LinearGradient(
                    colors: [GatewayTheme.accentGlow, Color.clear],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 0.4)
                )
                .frame(height: 260)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
            .task {
                await vm.loadAppSettings()
                await vm.load()
            }
        }
    }

    // MARK: Setup Banner

    private var setupBanner: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(1)) {
            Text("Gateway URL required")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(GatewayTheme.warn)
            Text("Enter your server URL below to connect this app to your gateway.")
                .font(.system(size: 13))
                .foregroundStyle(GatewayTheme.textDim)
                .lineSpacing(4)
        }
        .padding(GatewayTheme.spacing(4))
        .background(GatewayTheme.warn.opacity(0.1))
        .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusMd).stroke(GatewayTheme.warn.opacity(0.35), lineWidth: 1))
    }

    // MARK: API Key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
            sectionHeader("API Key", icon: "key.fill")
            Text("Used to authenticate write operations, intercept access, and config changes.")
                .font(.system(size: 12))
                .foregroundStyle(GatewayTheme.textFaint)
                .lineSpacing(4)

            HStack {
                Group {
                    if showApiKey {
                        TextField("API key", text: $vm.apiKeyInput)
                            .font(.system(size: 14, design: .monospaced))
                    } else {
                        SecureField("API key", text: $vm.apiKeyInput)
                            .font(.system(size: 14, design: .monospaced))
                    }
                }
                .foregroundStyle(GatewayTheme.text)
                .padding(.leading, GatewayTheme.spacing(4))
                .padding(.vertical, GatewayTheme.spacing(3))

                Button {
                    showApiKey.toggle()
                } label: {
                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                        .font(.system(size: 18))
                        .foregroundStyle(GatewayTheme.textDim)
                        .padding(GatewayTheme.spacing(3))
                }
                .accessibilityLabel(showApiKey ? "Hide API key" : "Show API key")
            }
            .background(GatewayTheme.surface)
            .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusMd).stroke(GatewayTheme.border, lineWidth: 1))
            .onChange(of: vm.apiKeyInput) { _, _ in vm.appDirty = true }
        }
    }

    // MARK: App Settings

    private var appSettingsSection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
            sectionHeader("App Settings", icon: "gearshape.fill")
            Text("Persisted on this device.").appHint()

            appField("Gateway URL", $vm.gatewayUrl, placeholder: "https://your-server.rork.app")
            appField("Proxy Host", $vm.proxyHost, placeholder: "https://example.com")
            appField("Allowed Origins", $vm.allowedOrigins, placeholder: "*")

            if vm.appDirty {
                Button {
                    Task { await vm.saveAppSettings() }
                } label: {
                    HStack(spacing: GatewayTheme.spacing(2)) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Save app settings")
                    }
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(GatewayTheme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, GatewayTheme.spacing(3.5))
                    .background(GatewayTheme.accent)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                }
                .accessibilityLabel("Save app settings to device")
            }
        }
    }

    private func appField(_ label: String, _ binding: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(1)) {
            Text(label).fieldLabelStyle()
            TextField(placeholder, text: binding)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(GatewayTheme.text)
                .padding(GatewayTheme.spacing(3))
                .background(GatewayTheme.surface)
                .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onChange(of: binding.wrappedValue) { _, _ in vm.appDirty = true }
        }
    }

    // MARK: Runtime Config

    private var runtimeConfigSection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
            sectionHeader("Runtime Config", icon: "slider.horizontal.3")
            Text("Overrides stored in the gateway. Take precedence over env vars.").appHint()

            if vm.configIsLoading {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    ProgressView().scaleEffect(0.7).tint(GatewayTheme.accent)
                    Text("Loading config...").font(.system(size: 13)).foregroundStyle(GatewayTheme.textDim)
                }
                .padding(GatewayTheme.spacing(3))
            } else if let err = vm.configError {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    Image(systemName: "shield.fill").foregroundStyle(GatewayTheme.danger)
                    Text(err).font(.system(size: 13)).foregroundStyle(GatewayTheme.danger)
                }
                .padding(GatewayTheme.spacing(3))
            } else {
                ForEach(SettingsViewModel.configGroups, id: \.title) { group in
                    VStack(spacing: 0) {
                        HStack(spacing: GatewayTheme.spacing(2)) {
                            Image(systemName: group.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(GatewayTheme.accent)
                            Text(group.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(GatewayTheme.text)
                                .kerning(0.5)
                            Spacer()
                        }
                        .padding(.horizontal, GatewayTheme.spacing(4))
                        .padding(.vertical, GatewayTheme.spacing(2.5))
                        .background(GatewayTheme.bgElevated)

                        ForEach(group.keys, id: \.self) { key in
                            configFieldRow(key)
                        }
                    }
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
                    .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusMd).stroke(GatewayTheme.border, lineWidth: 1))
                }

                if !vm.runtimeConfig.isEmpty {
                    HStack {
                        Text("\(vm.runtimeConfig.count) override\(vm.runtimeConfig.count != 1 ? "s" : "") active")
                            .monoFont(size: 11)
                            .foregroundStyle(GatewayTheme.textFaint)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await vm.clearRuntimeConfig() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash").font(.system(size: 13))
                                Text("Revert to defaults")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(GatewayTheme.danger)
                            .padding(.vertical, GatewayTheme.spacing(2))
                            .padding(.horizontal, GatewayTheme.spacing(3))
                            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                        }
                        .disabled(vm.isClearingConfig)
                        .accessibilityLabel("Revert runtime config to defaults")
                    }
                }

                if vm.configEditDirty {
                    Button {
                        Task { await vm.saveRuntimeConfig() }
                    } label: {
                        HStack(spacing: GatewayTheme.spacing(2)) {
                            if vm.isSavingConfig {
                                ProgressView().scaleEffect(0.7).tint(GatewayTheme.bg)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                            }
                            Text(vm.isSavingConfig ? "Saving..." : "Save runtime config")
                        }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(GatewayTheme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, GatewayTheme.spacing(3.5))
                        .background(GatewayTheme.accent)
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    }
                    .disabled(vm.isSavingConfig)
                }

                VStack(spacing: GatewayTheme.spacing(1.5)) {
                    Button {
                        Task { await vm.testConnection() }
                    } label: {
                        HStack(spacing: GatewayTheme.spacing(2)) {
                            if vm.isTesting {
                                ProgressView().scaleEffect(0.7).tint(GatewayTheme.accent)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(vm.isTesting ? "Testing..." : "Test Connection")
                        }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(GatewayTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, GatewayTheme.spacing(3.5))
                        .background(GatewayTheme.surface)
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                        .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                    }
                    .disabled(vm.isTesting)
                    .accessibilityLabel("Test gateway connection")

                    if let result = vm.testResult {
                        HStack(spacing: GatewayTheme.spacing(2)) {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 14))
                            Text(result.message)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(3)
                        }
                        .foregroundStyle(result.success ? GatewayTheme.ok : GatewayTheme.danger)
                        .padding(GatewayTheme.spacing(2.5))
                        .background(result.success ? GatewayTheme.ok.opacity(0.08) : GatewayTheme.danger.opacity(0.08))
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                        .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(result.success ? GatewayTheme.ok.opacity(0.25) : GatewayTheme.danger.opacity(0.25), lineWidth: 1))
                    }
                }
                .padding(.top, GatewayTheme.spacing(1.5))
            }
        }
    }

    private func configFieldRow(_ key: String) -> some View {
        let currentValue = fieldValues[key] ?? vm.runtimeConfig[key] ?? SettingsViewModel.fieldDefaults[key] ?? ""
        let label = SettingsViewModel.fieldLabels[key] ?? key
        let hint = SettingsViewModel.fieldHints[key]
        let defaultValue = SettingsViewModel.fieldDefaults[key] ?? ""

        return VStack(alignment: .leading, spacing: GatewayTheme.spacing(1.5)) {
            Text(label).fieldLabelStyle()
            TextField(defaultValue.isEmpty ? "Enter value..." : defaultValue, text: Binding(
                get: { fieldValues[key] ?? currentValue },
                set: { newVal in
                    fieldValues[key] = newVal
                    vm.updateConfigField(key, value: newVal)
                }
            ))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(GatewayTheme.text)
            .padding(GatewayTheme.spacing(2.5))
            .background(GatewayTheme.surfaceAlt)
            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
            .autocapitalization(.none)
            .autocorrectionDisabled()
            if let hint = hint {
                Text(hint)
                    .monoFont(size: 9)
                    .foregroundStyle(GatewayTheme.textFaint)
            }
        }
        .padding(GatewayTheme.spacing(3))
        .background(GatewayTheme.surface)
        .overlay(alignment: .bottom) {
            if key != SettingsViewModel.configGroups.last?.keys.last {
                Divider().background(GatewayTheme.border).padding(.horizontal, GatewayTheme.spacing(3))
            }
        }
    }

    // MARK: Tunnels

    private var tunnelsSection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
            sectionHeader("Proxy Tunnels", icon: "network")
            Text("Self-hosted Pangolin/frp-style tunnels replacing Cloudflare Workers.").appHint()

            if let status = vm.proxyStatus {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    statusCard("\(status.tunnelsRunning)", "running", GatewayTheme.accent)
                    statusCard("\(status.tunnelsStopped)", "stopped", GatewayTheme.textFaint)
                    statusCard("\(status.totalActiveConns)", "connections", GatewayTheme.accent)
                    statusCard(String(format: "%.1f KB", Double(status.totalBytesTransferred) / 1024), "transferred", GatewayTheme.accent)
                }
            }

            if vm.tunnelsLoading {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    ProgressView().scaleEffect(0.7).tint(GatewayTheme.accent)
                    Text("Loading tunnels...").font(.system(size: 13)).foregroundStyle(GatewayTheme.textDim)
                }
                .padding(GatewayTheme.spacing(3))
            } else if let err = vm.tunnelsError {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(GatewayTheme.warn)
                    Text(err).font(.system(size: 12)).foregroundStyle(GatewayTheme.warn)
                }
                .padding(GatewayTheme.spacing(3))
            } else if vm.tunnels.isEmpty {
                EmptyStateView(icon: "network", title: "No active tunnels", subtitle: "Create one from the Proxies tab.")
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.tunnels) { tunnel in
                        tunnelRow(tunnel)
                        if tunnel.id != vm.tunnels.last?.id {
                            Divider().background(GatewayTheme.border)
                        }
                    }
                }
                .cardSurface()
            }

            Button {
                Task { await vm.refreshTunnels() }
            } label: {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                    Text("Refresh tunnels").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(GatewayTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, GatewayTheme.spacing(2))
            }
            .accessibilityLabel("Refresh proxy tunnels")
        }
    }

    private func tunnelRow(_ tunnel: ProxyTunnel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: GatewayTheme.spacing(1.5)) {
                    Circle()
                        .fill(tunnel.status == "running" ? GatewayTheme.ok : tunnel.status == "error" ? GatewayTheme.danger : GatewayTheme.textFaint)
                        .frame(width: 7, height: 7)
                    Text(tunnel.name)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(GatewayTheme.text)
                }
                Text(":\(tunnel.localPort) → :\(tunnel.remotePort) · \(tunnel.activeConns) conns")
                    .monoFont(size: 10)
                    .foregroundStyle(GatewayTheme.textDim)
            }
            Spacer()
            Text(tunnel.status)
                .monoFont(size: 10)
                .foregroundStyle(tunnel.status == "running" ? GatewayTheme.ok : GatewayTheme.textFaint)
                .textCase(.uppercase)
        }
        .padding(GatewayTheme.spacing(3))
    }

    private func statusCard(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: GatewayTheme.spacing(1)) {
            Text(value)
                .monoFont(size: 20, weight: .heavy)
                .foregroundStyle(color)
            Text(label)
                .monoFont(size: 9, weight: .bold)
                .foregroundStyle(GatewayTheme.textFaint)
                .kerning(1)
        }
        .frame(maxWidth: .infinity)
        .padding(GatewayTheme.spacing(3))
        .cardSurface()
    }

    // MARK: Gateway URLs

    private var gatewayUrlsSection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
            sectionHeader("Gateway URLs & APIs", icon: "wrench.fill")
            VStack(spacing: 0) {
                copyRow("Gateway URL", vm.gatewayUrl.isEmpty ? "Not configured" : vm.gatewayUrl)
                Divider().background(GatewayTheme.border)
                copyRow("Health", "\(vm.gatewayUrl)/health")
                Divider().background(GatewayTheme.border)
                copyRow("Config API", "\(vm.gatewayUrl)/api/config")
                Divider().background(GatewayTheme.border)
                copyRow("Proxies API", "\(vm.gatewayUrl)/api/proxies")
                Divider().background(GatewayTheme.border)
                copyRow("Tunnels API", "\(vm.gatewayUrl)/api/proxy/tunnels")
                Divider().background(GatewayTheme.border)
                copyRow("Intercepts API", "\(vm.gatewayUrl)/api/intercepts")
                Divider().background(GatewayTheme.border)
                copyRow("HAR Export", "\(vm.gatewayUrl)/api/intercepts/har")
            }
            .cardElevated()
        }
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .monoFont(size: 11)
                .foregroundStyle(GatewayTheme.textFaint)
            Spacer()
            Text(value)
                .monoFont(size: 11)
                .foregroundStyle(GatewayTheme.textDim)
                .lineLimit(1)
            Button {
                UIPasteboard.general.string = value
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(GatewayTheme.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Copy \(label)")
        }
        .padding(GatewayTheme.spacing(3))
    }

    // MARK: Architecture

    private var architectureSection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
            sectionHeader("Architecture", icon: "square.3.layers.3d")

            VStack(spacing: 0) {
                archCard("Expo App", "Dashboard for managing proxies, viewing intercepted traffic, running reconnaissance, and configuring the gateway.", "apps.iphone")
                Rectangle().fill(GatewayTheme.borderStrong).frame(width: 2, height: 16).padding(.leading, GatewayTheme.spacing(4) + 19)
                archCard("Edge Gateway", "Self-hosted Node.js server — wildcard DNS routing, WebSocket passthrough, HTML rewriting, and security headers on every request.", "shield.fill")
                Rectangle().fill(GatewayTheme.borderStrong).frame(width: 2, height: 16).padding(.leading, GatewayTheme.spacing(4) + 19)
                archCard("In-Memory Store", "Persistent storage for proxies, items, config overrides, intercept captures, and phishlets.", "cpu.fill")
            }
        }
    }

    private func archCard(_ title: String, _ body: String, _ icon: String) -> some View {
        HStack(spacing: GatewayTheme.spacing(3)) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(GatewayTheme.accent)
                .frame(width: 40, height: 40)
                .background(GatewayTheme.accentGlow)
                .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GatewayTheme.text)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(GatewayTheme.textDim)
                    .lineSpacing(3)
            }
        }
        .padding(GatewayTheme.spacing(3.5))
        .cardSurface()
    }

    // MARK: Capabilities

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
            sectionHeader("Capabilities", icon: "puzzlepiece.extension.fill")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: GatewayTheme.spacing(2)) {
                capCard("Tunnel management", "Create, start, stop, and delete proxy tunnels with live stats and health monitoring.", "network")
                capCard("Per-proxy JS injection", "Inject custom JavaScript into proxied HTML pages for data collection.", "puzzlepiece.extension.fill")
                capCard("Automated phishlet generation", "One-tap recon pipeline: capture → generate → iterate → refine.", "cpu.fill")
                capCard("API key auth", "Bearer token authentication on all write endpoints and config changes.", "key.fill")
                capCard("Runtime config", "Live config overrides — no redeploy needed.", "slider.horizontal.3")
                capCard("HAR replay engine", "Export captures as HAR and replay full sessions against any target.", "arrow.right")
            }
        }
    }

    private func capCard(_ title: String, _ body: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(GatewayTheme.accent)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GatewayTheme.text)
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(GatewayTheme.textDim)
                .lineSpacing(4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GatewayTheme.spacing(3.5))
        .background(GatewayTheme.bgElevated)
        .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusMd).stroke(GatewayTheme.border, lineWidth: 1))
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: GatewayTheme.spacing(2)) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(GatewayTheme.accent)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GatewayTheme.text)
        }
    }
}

private extension View {
    func appHint() -> some View {
        self
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(GatewayTheme.textFaint)
            .lineSpacing(3)
    }
}
