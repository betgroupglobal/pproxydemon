import SwiftUI

// MARK: - Proxies Screen

struct ProxiesScreen: View {
    @State private var vm = ProxiesViewModel()
    @State private var aiVM = ProxyConfigAssistantViewModel()
    @State private var showConfigAssistant = false

    var body: some View {
        NavigationStack {
            ZStack {
                GatewayTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(4)) {
                        headerSection
                        createForm
                        proxyListSection
                        aiAssistantBanner
                        serverLaunchSection
                    }
                    .padding(.horizontal, GatewayTheme.spacing(4))
                    .padding(.top, GatewayTheme.spacing(6))
                    .padding(.bottom, GatewayTheme.spacing(12))
                }
                .scrollIndicators(.hidden)
                .refreshable { await vm.refresh() }
                .sheet(isPresented: $showConfigAssistant) {
                    configAssistantSheet
                }

                LinearGradient(
                    colors: [GatewayTheme.accentGlow, Color.clear],
                    startPoint: UnitPoint(x: 0.1, y: 0),
                    endPoint: UnitPoint(x: 0.9, y: 0.5)
                )
                .frame(height: 320)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
            .task { await vm.load(); await vm.fetchServers() }
            .onChange(of: showConfigAssistant) { _, shown in
                if shown { aiVM.assistantResult = ""; aiVM.assistantError = nil }
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: GatewayTheme.spacing(1.5)) {
                Text("EDGE PROXIES").eyebrowStyle()
                Text("Route any domain")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(GatewayTheme.text)
                    .tracking(-0.5)
                Text("Add a target and it goes live instantly. Every request captured for the analyser.")
                    .font(.system(size: 13))
                    .foregroundStyle(GatewayTheme.textDim)
                    .lineSpacing(4)
            }
            Spacer()
            if !vm.proxies.isEmpty {
                VStack(alignment: .trailing, spacing: GatewayTheme.spacing(1.5)) {
                    pillLabel("\(vm.proxies.count)", "total", bg: GatewayTheme.surface, fg: GatewayTheme.text)
                    pillLabel("\(vm.activeCount)", "active", bg: GatewayTheme.ok.opacity(0.08), fg: GatewayTheme.ok)
                }
            }
        }
    }

    @ViewBuilder
    private func pillLabel(_ value: String, _ label: String, bg: Color, fg: Color) -> some View {
        HStack(spacing: GatewayTheme.spacing(1.5)) {
            Text(value).monoFont(size: 16, weight: .heavy).foregroundStyle(fg)
            Text(label).monoFont(size: 9, weight: .bold).foregroundStyle(fg.opacity(0.7)).kerning(0.5)
        }
        .padding(.horizontal, GatewayTheme.spacing(2.5))
        .padding(.vertical, GatewayTheme.spacing(1))
        .background(bg)
        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
        .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(fg.opacity(0.35), lineWidth: 1))
    }

    // MARK: Create Form

    private var createForm: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
            Text("TARGET DOMAIN").fieldLabelStyle()
            TextField("https://api.example.com", text: $vm.targetUrl)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(GatewayTheme.text)
                .padding(GatewayTheme.spacing(3))
                .background(GatewayTheme.surface)
                .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            Text("NAME (optional)").fieldLabelStyle()
            TextField("e.g. Example API", text: $vm.proxyName)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(GatewayTheme.text)
                .padding(GatewayTheme.spacing(3))
                .background(GatewayTheme.surface)
                .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                .autocapitalization(.none)

            if let err = vm.formError {
                Text(err).font(.system(size: 12)).foregroundStyle(GatewayTheme.danger)
            }

            Button {
                Task { await vm.createProxy() }
            } label: {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    if vm.isCreating {
                        ProgressView().scaleEffect(0.7).tint(GatewayTheme.bg)
                    } else {
                        Image(systemName: "network")
                    }
                    Text(vm.isCreating ? "Deploying…" : "Deploy proxy")
                }
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(GatewayTheme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, GatewayTheme.spacing(3.5))
                .background(GatewayTheme.accent)
                .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
            }
            .disabled(vm.isCreating)
            .accessibilityLabel(vm.isCreating ? "Deploying proxy" : "Deploy proxy")
        }
        .padding(GatewayTheme.spacing(4))
        .cardElevated()
    }

    // MARK: Proxy List

    private var proxyListSection: some View {
        Group {
            if let err = vm.error {
                OfflineCardView(message: err) { Task { await vm.refresh() } }
            } else if vm.isLoading {
                VStack(spacing: GatewayTheme.spacing(3)) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonCardView(height: 140) }
                }
            } else if vm.proxies.isEmpty {
                EmptyStateView(icon: "network", title: "No targets yet", subtitle: "Add a domain above to start routing traffic through the gateway.")
            } else {
                VStack(spacing: GatewayTheme.spacing(3)) {
                    Text("TARGETS · \(vm.proxies.count)").sectionTitleStyle()
                    ForEach(vm.proxies) { proxy in
                        ProxyCardView(proxy: proxy, vm: vm)
                    }
                }
            }
        }
    }

    // MARK: AI Assistant Banner

    private var aiAssistantBanner: some View {
        Button {
            showConfigAssistant = true
            aiVM.userIntent = ""
        } label: {
            HStack(spacing: GatewayTheme.spacing(3)) {
                ZStack {
                    Circle()
                        .fill(GatewayTheme.cyan.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18))
                        .foregroundStyle(GatewayTheme.cyan)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Proxy Config Assistant")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GatewayTheme.cyan)
                    Text("Generate configs with Kimi K2.7 AI")
                        .monoFont(size: 11)
                        .foregroundStyle(GatewayTheme.textDim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GatewayTheme.cyan.opacity(0.5))
            }
            .padding(GatewayTheme.spacing(3.5))
            .background(
                RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
                    .fill(GatewayTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
                            .stroke(GatewayTheme.cyan.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .accessibilityLabel("Open Proxy Config Assistant")
    }

    // MARK: Config Assistant Sheet

    private var configAssistantSheet: some View {
        NavigationStack {
            ZStack {
                GatewayTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(4)) {
                        // Header
                        HStack(spacing: GatewayTheme.spacing(3)) {
                            ZStack {
                                Circle()
                                    .fill(GatewayTheme.cyan.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 20))
                                    .foregroundStyle(GatewayTheme.cyan)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Config Assistant")
                                    .font(.system(size: 18, weight: .heavy))
                                    .foregroundStyle(GatewayTheme.text)
                                Text("Powered by Kimi K2.7 Code HighSpeed")
                                    .monoFont(size: 11)
                                    .foregroundStyle(GatewayTheme.textFaint)
                            }
                            Spacer()
                        }

                        // Quick templates
                        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
                            Text("QUICK START").fieldLabelStyle()
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: GatewayTheme.spacing(2)
                            ) {
                                ForEach(ProxyUseCase.allCases) { useCase in
                                    useCaseButton(useCase)
                                }
                            }
                        }

                        // Custom input
                        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
                            Text("OR DESCRIBE YOUR SETUP").fieldLabelStyle()
                            TextField(
                                "e.g. Route /api to my Node backend at port 3001 with rate limiting at 50 req/s…",
                                text: $aiVM.userIntent,
                                axis: .vertical
                            )
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(GatewayTheme.text)
                            .lineLimit(3...6)
                            .padding(GatewayTheme.spacing(3))
                            .background(GatewayTheme.surface)
                            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                            if !aiVM.userIntent.trimmingCharacters(in: .whitespaces).isEmpty {
                                Button {
                                    Task { await aiVM.generateConfig() }
                                } label: {
                                    HStack(spacing: GatewayTheme.spacing(2)) {
                                        if aiVM.isGenerating {
                                            ProgressView().scaleEffect(0.7).tint(GatewayTheme.bg)
                                        } else {
                                            Image(systemName: "sparkles")
                                        }
                                        Text(aiVM.isGenerating ? "Generating…" : "Generate config")
                                    }
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(GatewayTheme.bg)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, GatewayTheme.spacing(3))
                                    .background(GatewayTheme.cyan)
                                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                                }
                                .disabled(aiVM.isGenerating)
                            }
                        }

                        // Error
                        if let err = aiVM.assistantError {
                            OfflineCardView(message: err) {
                                Task { await aiVM.generateConfig() }
                            }
                        }

                        // Loading / Result
                        if aiVM.isGenerating || !aiVM.assistantResult.isEmpty {
                            VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
                                if aiVM.isGenerating {
                                    HStack(spacing: GatewayTheme.spacing(1.5)) {
                                        ProgressView().scaleEffect(0.7).tint(GatewayTheme.cyan)
                                        Text("Kimi K2.7 is writing your config…")
                                            .monoFont(size: 10)
                                            .foregroundStyle(GatewayTheme.cyan)
                                    }
                                    .padding(.horizontal, GatewayTheme.spacing(2.5))
                                    .padding(.vertical, GatewayTheme.spacing(1))
                                    .background(GatewayTheme.cyan.opacity(0.08))
                                    .clipShape(.capsule)
                                }

                                if !aiVM.assistantResult.isEmpty {
                                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(1.5)) {
                                        Text("GENERATED CONFIGURATION")
                                            .monoFont(size: 10, weight: .heavy)
                                            .foregroundStyle(GatewayTheme.textFaint)
                                            .kerning(1)
                                        Text(aiVM.assistantResult)
                                            .monoFont(size: 12)
                                            .foregroundStyle(GatewayTheme.text)
                                            .lineSpacing(4)
                                    }
                                    .padding(GatewayTheme.spacing(4))
                                    .cardSurface()
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            UIPasteboard.general.string = aiVM.assistantResult
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 12))
                                                .foregroundStyle(GatewayTheme.cyan)
                                                .frame(width: 36, height: 36)
                                        }
                                        .offset(x: -4, y: 4)
                                    }

                                    // Explain button
                                    Button {
                                        Task { await aiVM.explainConfig(aiVM.assistantResult) }
                                    } label: {
                                        HStack(spacing: GatewayTheme.spacing(2)) {
                                            Image(systemName: "text.magnifyingglass")
                                            Text("Explain this config in plain English")
                                        }
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(GatewayTheme.cyan)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, GatewayTheme.spacing(2.5))
                                        .background(GatewayTheme.cyan.opacity(0.08))
                                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                                        .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.cyan.opacity(0.25), lineWidth: 1))
                                    }
                                    .disabled(aiVM.isGenerating)
                                }
                            }
                        }
                    }
                    .padding(GatewayTheme.spacing(4))
                    .padding(.bottom, GatewayTheme.spacing(12))
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Config Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showConfigAssistant = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Use Case Button

    private func useCaseButton(_ useCase: ProxyUseCase) -> some View {
        Button {
            if useCase == .custom {
                // Focus the text field — user types custom intent
            } else {
                aiVM.userIntent = ""
                Task { await aiVM.suggestRules(for: useCase) }
            }
        } label: {
            HStack(spacing: GatewayTheme.spacing(1.5)) {
                Image(systemName: useCase.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(GatewayTheme.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text(useCase.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GatewayTheme.text)
                    Text(useCase.description)
                        .font(.system(size: 9))
                        .foregroundStyle(GatewayTheme.textFaint)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(GatewayTheme.spacing(2.5))
            .background(GatewayTheme.surface)
            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
        }
        .disabled(aiVM.isGenerating)
    }

    // MARK: Server Launch

    private var serverLaunchSection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
            Divider().background(GatewayTheme.border).padding(.vertical, GatewayTheme.spacing(2))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROXY SERVERS").eyebrowStyle()
                    Text("Launch tunnel hosts")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(GatewayTheme.text)
                        .tracking(-0.5)
                    Text("Spin up dedicated proxy server instances. AI generates the optimal config.")
                        .font(.system(size: 13))
                        .foregroundStyle(GatewayTheme.textDim)
                        .lineSpacing(4)
                }
                Spacer()
                if vm.runningServerCount > 0 {
                    HStack(spacing: GatewayTheme.spacing(1.5)) {
                        Circle().fill(GatewayTheme.ok).frame(width: 6, height: 6)
                        Text("\(vm.runningServerCount) running")
                            .monoFont(size: 11, weight: .bold)
                            .foregroundStyle(GatewayTheme.ok)
                    }
                    .padding(.horizontal, GatewayTheme.spacing(2.5))
                    .padding(.vertical, GatewayTheme.spacing(1))
                    .background(GatewayTheme.ok.opacity(0.1))
                    .clipShape(.capsule)
                    .overlay(Capsule().stroke(GatewayTheme.ok.opacity(0.25), lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
                Text("TARGET HOST").fieldLabelStyle()
                TextField("api.example.com", text: $vm.svrTarget)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(GatewayTheme.text)
                    .padding(GatewayTheme.spacing(3))
                    .background(GatewayTheme.surface)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                HStack(spacing: GatewayTheme.spacing(2.5)) {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(1)) {
                        Text("NAME").fieldLabelStyle()
                        TextField("e.g. prod-vpn", text: $vm.svrName)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(GatewayTheme.text)
                            .padding(GatewayTheme.spacing(3))
                            .background(GatewayTheme.surface)
                            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                            .autocapitalization(.none)
                    }
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(1)) {
                        Text("PORT").fieldLabelStyle()
                        TextField("12000", text: $vm.svrPort)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(GatewayTheme.text)
                            .padding(GatewayTheme.spacing(3))
                            .background(GatewayTheme.surface)
                            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                            .keyboardType(.numberPad)
                            .frame(width: 100)
                    }
                }

                if let config = vm.svrConfig {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(1)) {
                        Text("Generated config")
                            .monoFont(size: 10, weight: .bold)
                            .foregroundStyle(GatewayTheme.accent)
                            .kerning(0.3)
                        Text(config)
                            .monoFont(size: 10)
                            .foregroundStyle(GatewayTheme.textDim)
                            .lineLimit(6)
                            .lineSpacing(4)
                    }
                    .padding(GatewayTheme.spacing(2))
                    .background(GatewayTheme.bg.opacity(0.8))
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.accent, lineWidth: 1))
                }

                if let err = vm.svrError {
                    Text(err).font(.system(size: 12)).foregroundStyle(GatewayTheme.danger)
                }

                HStack(spacing: GatewayTheme.spacing(2.5)) {
                    Button {
                        Task { await vm.configureServer() }
                    } label: {
                        HStack(spacing: GatewayTheme.spacing(1.5)) {
                            if vm.isConfiguring {
                                ProgressView().scaleEffect(0.6).tint(GatewayTheme.accent)
                            } else {
                                Image(systemName: "cpu.fill").font(.system(size: 14))
                            }
                            Text(vm.isConfiguring ? "Generating…" : "Generate config")
                        }
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(GatewayTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, GatewayTheme.spacing(1.8))
                        .background(Color.clear)
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                        .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.accent, lineWidth: 1))
                    }
                    .disabled(vm.isConfiguring)

                    Button {
                        Task { await vm.launchServer() }
                    } label: {
                        HStack(spacing: GatewayTheme.spacing(1.5)) {
                            if vm.isLaunching {
                                ProgressView().scaleEffect(0.6).tint(GatewayTheme.bg)
                            } else {
                                Image(systemName: "play.fill").font(.system(size: 14))
                            }
                            Text(vm.isLaunching ? "Launching…" : "Launch server")
                        }
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(GatewayTheme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, GatewayTheme.spacing(1.8))
                        .background(GatewayTheme.accent)
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    }
                    .disabled(vm.isLaunching)
                }
            }
            .padding(GatewayTheme.spacing(4))
            .cardElevated()

            if !vm.servers.isEmpty {
                VStack(spacing: GatewayTheme.spacing(3)) {
                    Text("INSTANCES · \(vm.servers.count)").sectionTitleStyle()
                    ForEach(vm.servers) { srv in
                        ServerInstanceCardView(srv: srv, vm: vm)
                    }
                }
            }
        }
    }
}

// MARK: - Proxy Card

struct ProxyCardView: View {
    let proxy: Proxy
    let vm: ProxiesViewModel

    @State private var interceptOn: Bool

    init(proxy: Proxy, vm: ProxiesViewModel) {
        self.proxy = proxy
        self.vm = vm
        _interceptOn = State(initialValue: proxy.interceptEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(proxy.name.isEmpty ? proxy.slug : proxy.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GatewayTheme.text)
                    Text(proxy.targetUrl)
                        .monoFont(size: 11)
                        .foregroundStyle(GatewayTheme.textDim)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(proxy.enabled ? GatewayTheme.ok : GatewayTheme.textFaint)
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: GatewayTheme.spacing(4)) {
                Label("\(proxy.hits) hits", systemImage: "bolt.fill")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(GatewayTheme.textFaint)
                if let tid = proxy.tunnelId {
                    Label("Tunnel \(tid)", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(GatewayTheme.textFaint)
                }
            }

            // Intercept toggle — routes through ViewModel
            HStack {
                Toggle("Intercept", isOn: $interceptOn)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(GatewayTheme.textDim)
                    .tint(GatewayTheme.warn)
                    .onChange(of: interceptOn) { _, newValue in
                        Task { await vm.toggleIntercept(for: proxy.id, to: newValue) }
                    }
                Spacer()
                Button(role: .destructive) {
                    Task { await vm.deleteProxy(proxy.id) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(GatewayTheme.danger)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Delete proxy \(proxy.name.isEmpty ? proxy.slug : proxy.name)")
            }
        }
        .padding(GatewayTheme.spacing(4))
        .cardSurface()
        .onChange(of: proxy.interceptEnabled) { _, newValue in
            interceptOn = newValue
        }
    }
}

// MARK: - Server Instance Card

struct ServerInstanceCardView: View {
    let srv: ProxyServerInstance
    let vm: ProxiesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(2.5)) {
            HStack {
                HStack(spacing: GatewayTheme.spacing(1.5)) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(srv.name)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(GatewayTheme.text)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: GatewayTheme.spacing(2)) {
                    Button {
                        Task { await vm.fetchLogs(for: srv.id) }
                    } label: {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(GatewayTheme.textDim)
                            .frame(width: 44, height: 44)
                            .background(GatewayTheme.surface)
                            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    }
                    .accessibilityLabel("View logs for \(srv.name)")
                    if srv.status == "running" || srv.status == "degraded" {
                        Button {
                            Task { await vm.stopServer(srv.id) }
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(GatewayTheme.danger)
                                .frame(width: 44, height: 44)
                                .background(GatewayTheme.danger.opacity(0.12))
                                .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                        }
                        .accessibilityLabel("Stop server \(srv.name)")
                        .disabled(vm.isStopping)
                    }
                }
            }

            Text("Port \(srv.port) · PID \(srv.pid) · \(srv.tunnelCount) tunnels")
                .monoFont(size: 10)
                .foregroundStyle(GatewayTheme.textDim)

            if srv.status == "running" {
                Text("Up \(GatewayTheme.formatUptime(srv.uptime))\(srv.health?.status != nil ? " · \(srv.health!.status)" : "")")
                    .monoFont(size: 9)
                    .foregroundStyle(GatewayTheme.ok)
            } else {
                Text(srv.status)
                    .monoFont(size: 9)
                    .foregroundStyle(srv.status == "crashed" ? GatewayTheme.danger : GatewayTheme.warn)
            }

            if vm.showLogsFor == srv.id, let logs = vm.logsText {
                Text(String(logs.suffix(2000)))
                    .monoFont(size: 9)
                    .foregroundStyle(GatewayTheme.textDim)
                    .lineSpacing(4)
                    .padding(GatewayTheme.spacing(2))
                    .background(GatewayTheme.bg.opacity(0.5))
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    .frame(maxHeight: 200)
            }
        }
        .padding(GatewayTheme.spacing(4))
        .cardSurface()
    }

    private var statusColor: Color {
        switch srv.status {
        case "running": return GatewayTheme.ok
        case "launching": return GatewayTheme.warn
        default: return GatewayTheme.textFaint
        }
    }
}
