import SwiftUI

// MARK: - Intercepts Screen

struct InterceptsScreen: View {
    @State private var vm = InterceptsViewModel()
    @State private var aiVM = InterceptAnalysisViewModel()
    @State private var showAISheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                GatewayTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(4)) {
                        headerSection
                        quickActions
                        contentSection
                    }
                    .padding(.horizontal, GatewayTheme.spacing(4))
                    .padding(.top, GatewayTheme.spacing(6))
                    .padding(.bottom, GatewayTheme.spacing(12))
                }
                .scrollIndicators(.hidden)
                .refreshable { await vm.refresh() }
                .sheet(isPresented: $vm.showReplay) {
                    replayModal
                }
                .sheet(isPresented: $showAISheet) {
                    aiAnalysisSheet
                }

                LinearGradient(
                    colors: [GatewayTheme.warn.opacity(0.12), Color.clear],
                    startPoint: UnitPoint(x: 0.1, y: 0),
                    endPoint: UnitPoint(x: 0.9, y: 0.5)
                )
                .frame(height: 300)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
            .task { await vm.load() }
            .onChange(of: showAISheet) { _, shown in
                if shown { aiVM.analysisResult = ""; aiVM.analysisError = nil }
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(1)) {
            HStack(spacing: GatewayTheme.spacing(1.5)) {
                Text("INTERCEPT LAB")
                    .foregroundStyle(GatewayTheme.warn)
                    .eyebrowStyle()
                if vm.isRefreshing, !vm.isLoading {
                    ProgressView().scaleEffect(0.6).tint(GatewayTheme.warn)
                }
            }
            HStack(spacing: GatewayTheme.spacing(2)) {
                Text("Captures")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(GatewayTheme.text)
                    .tracking(-0.5)
                if vm.captures.count > 0 {
                    Text("\(vm.captures.count)")
                        .monoFont(size: 12, weight: .heavy)
                        .foregroundStyle(GatewayTheme.warn)
                        .padding(.horizontal, GatewayTheme.spacing(2))
                        .padding(.vertical, 2)
                        .background(GatewayTheme.warn.opacity(0.15))
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(GatewayTheme.warn.opacity(0.4), lineWidth: 1))
                }
            }
            if let updated = vm.lastUpdatedStr {
                Text("LIVE · \(updated)")
                    .monoFont(size: 10, weight: .bold)
                    .foregroundStyle(GatewayTheme.warn.opacity(0.7))
                    .kerning(1)
            }
        }
    }

    // MARK: Quick Actions

    private var quickActions: some View {
        HStack(spacing: GatewayTheme.spacing(2)) {
            if !vm.captures.isEmpty {
                actionButton("Export HAR", icon: "square.and.arrow.down.fill", fg: GatewayTheme.accent) {
                    Task {
                        if let result = await vm.exportHAR() {
                            UIPasteboard.general.string = result.harJson
                        }
                    }
                }
                .disabled(vm.isExportingHAR)

                actionButton("Replay", icon: "play.fill", fg: GatewayTheme.cyan) {
                    vm.showReplay = true
                    vm.replayResult = nil
                }

                actionButton("Clear", icon: "trash.fill", fg: GatewayTheme.danger) {
                    Task { await vm.deleteAll() }
                }
                .disabled(vm.isDeleting)
            }
        }
    }

    private func actionButton(_ label: String, icon: String, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: GatewayTheme.spacing(1.5)) {
                if vm.isExportingHAR && label == "Export HAR" {
                    ProgressView().scaleEffect(0.6).tint(fg)
                } else {
                    Image(systemName: icon).font(.system(size: 14))
                }
                Text(label)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, GatewayTheme.spacing(2.5))
            .background(GatewayTheme.surface)
            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(fg, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }

    // MARK: Content

    private var contentSection: some View {
        Group {
            if let err = vm.error {
                OfflineCardView(message: err) { Task { await vm.load() } }
            } else if vm.isLoading {
                VStack(spacing: GatewayTheme.spacing(3)) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonCardView(height: 100) }
                }
            } else if vm.captures.isEmpty {
                EmptyStateView(
                    icon: "shield.exclamation",
                    title: "No captures yet",
                    subtitle: "Toggle \"Intercept\" on a proxy target to start capturing credentials, forms, and request data from proxied traffic.",
                    accent: GatewayTheme.warn
                )
            } else {
                VStack(spacing: GatewayTheme.spacing(3)) {
                    // AI Analysis banner
                    aiAnalysisBanner

                    ForEach(vm.groupedCaptures, id: \.slug) { group in
                        CaptureGroupCard(slug: group.slug, captures: group.captures, onAnalyze: { capture in
                            aiVM.analysisResult = ""
                            aiVM.analysisError = nil
                            showAISheet = true
                            Task { await aiVM.analyzeSingle(capture) }
                        })
                    }
                }
            }
        }
    }

    // MARK: AI Analysis Banner

    private var aiAnalysisBanner: some View {
        Button {
            showAISheet = true
            Task { await aiVM.analyzeAll(captures: vm.captures) }
        } label: {
            HStack(spacing: GatewayTheme.spacing(3)) {
                // Electric brain icon
                ZStack {
                    Circle()
                        .fill(GatewayTheme.accent.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18))
                        .foregroundStyle(GatewayTheme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Intercept Intelligence")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GatewayTheme.accent)
                    Text("Analyze \(vm.captures.count) captures with Kimi K2.7")
                        .monoFont(size: 11)
                        .foregroundStyle(GatewayTheme.textDim)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(GatewayTheme.accent.opacity(0.6))
            }
            .padding(GatewayTheme.spacing(3.5))
            .background(
                RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
                    .fill(GatewayTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
                            .stroke(GatewayTheme.accent.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .accessibilityLabel("Analyze all captures with AI")
    }

    // MARK: AI Analysis Sheet

    private var aiAnalysisSheet: some View {
        NavigationStack {
            ZStack {
                GatewayTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(4)) {
                        // Header
                        HStack(spacing: GatewayTheme.spacing(3)) {
                            ZStack {
                                Circle()
                                    .fill(GatewayTheme.accent.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 20))
                                    .foregroundStyle(GatewayTheme.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Intercept Intelligence")
                                    .font(.system(size: 18, weight: .heavy))
                                    .foregroundStyle(GatewayTheme.text)
                                Text("Powered by Kimi K2.7 Code HighSpeed")
                                    .monoFont(size: 11)
                                    .foregroundStyle(GatewayTheme.textFaint)
                            }
                            Spacer()
                        }

                        if let err = aiVM.analysisError {
                            OfflineCardView(message: err) {
                                Task { await aiVM.analyzeAll(captures: vm.captures) }
                            }
                        } else if aiVM.isAnalyzing {
                            VStack(spacing: GatewayTheme.spacing(3)) {
                                HStack(spacing: GatewayTheme.spacing(2)) {
                                    ProgressView().tint(GatewayTheme.accent)
                                    Text("Kimi K2.7 is analyzing your traffic…")
                                        .monoFont(size: 12)
                                        .foregroundStyle(GatewayTheme.textDim)
                                }

                                if !aiVM.analysisResult.isEmpty {
                                    analysisResultView
                                } else {
                                    // Skeleton while waiting for first token
                                    VStack(spacing: GatewayTheme.spacing(2)) {
                                        ForEach(0..<5, id: \.self) { i in
                                            SkeletonCardView(height: 20)
                                                .opacity(0.5 - Double(i) * 0.08)
                                        }
                                    }
                                }
                            }
                        } else if !aiVM.analysisResult.isEmpty {
                            analysisResultView
                        } else {
                            EmptyStateView(
                                icon: "brain.head.profile",
                                title: "Ready to analyze",
                                subtitle: "Close this sheet and tap the analysis banner to scan all captures, or tap a single capture for a deep-dive.",
                                accent: GatewayTheme.accent
                            )
                        }
                    }
                    .padding(GatewayTheme.spacing(4))
                    .padding(.bottom, GatewayTheme.spacing(12))
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("AI Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showAISheet = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !aiVM.analysisResult.isEmpty {
                        Button {
                            UIPasteboard.general.string = aiVM.analysisResult
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundStyle(GatewayTheme.accent)
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var analysisResultView: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
            if aiVM.isAnalyzing {
                HStack(spacing: GatewayTheme.spacing(1.5)) {
                    ProgressView().scaleEffect(0.7).tint(GatewayTheme.accent)
                    Text("Streaming response…")
                        .monoFont(size: 10)
                        .foregroundStyle(GatewayTheme.accent)
                }
                .padding(.horizontal, GatewayTheme.spacing(2.5))
                .padding(.vertical, GatewayTheme.spacing(1))
                .background(GatewayTheme.accent.opacity(0.1))
                .clipShape(.capsule)
            }

            Text(try! AttributedString(
                markdown: aiVM.analysisResult,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ))
            .font(.system(size: 13))
            .foregroundStyle(GatewayTheme.text)
            .lineSpacing(4)
            .padding(GatewayTheme.spacing(4))
            .cardSurface()
        }
    }

    // MARK: Replay Modal

    private var replayModal: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GatewayTheme.spacing(4)) {
                    Text("Paste a HAR (HTTP Archive) JSON blob and specify which proxy target to replay against. The engine sequentially executes every request, tracks cookies, and extracts tokens from the flow.")
                        .monoFont(size: 13)
                        .foregroundStyle(GatewayTheme.textDim)
                        .lineSpacing(4)

                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(1.5)) {
                        Text("PROXY SLUG").fieldLabelStyle()
                        TextField("e.g. my-target", text: $vm.replaySlug)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(GatewayTheme.text)
                            .padding(GatewayTheme.spacing(3))
                            .background(GatewayTheme.surface)
                            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(1.5)) {
                        Text("HAR JSON").fieldLabelStyle()
                        TextEditor(text: $vm.harPaste)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(GatewayTheme.text)
                            .frame(minHeight: 140)
                            .padding(GatewayTheme.spacing(2.5))
                            .background(GatewayTheme.surface)
                            .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                            .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                            .scrollContentBackground(.hidden)
                    }

                    if let err = vm.replayError {
                        Text(err).font(.system(size: 12)).foregroundStyle(GatewayTheme.danger)
                    }

                    Button {
                        Task { await vm.runReplay() }
                    } label: {
                        HStack(spacing: GatewayTheme.spacing(2)) {
                            if vm.isReplaying {
                                ProgressView().scaleEffect(0.7).tint(GatewayTheme.bg)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(vm.isReplaying ? "Replaying…" : "Run Replay")
                        }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(GatewayTheme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, GatewayTheme.spacing(3.5))
                        .background(GatewayTheme.cyan)
                        .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    }
                    .disabled(vm.isReplaying)
                    .accessibilityLabel("Run HAR replay")

                    if let report = vm.replayResult {
                        ReplayReportView(report: report)
                    }
                }
                .padding(GatewayTheme.spacing(4))
                .padding(.bottom, GatewayTheme.spacing(12))
            }
            .background(GatewayTheme.bg)
            .navigationTitle("Har Replay Engine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { vm.showReplay = false }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Capture Group Card

struct CaptureGroupCard: View {
    let slug: String
    let captures: [InterceptCapture]
    var onAnalyze: ((InterceptCapture) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(3)) {
            HStack {
                Text(slug)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(GatewayTheme.warn)
                Spacer()
                Text("\(captures.count) captures")
                    .monoFont(size: 10)
                    .foregroundStyle(GatewayTheme.textFaint)
            }

            ForEach(captures.prefix(10)) { cap in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: GatewayTheme.spacing(2)) {
                        Text(cap.method)
                            .monoFont(size: 10, weight: .heavy)
                            .foregroundStyle(GatewayTheme.methodColor(cap.method))
                            .frame(minWidth: 48, alignment: .leading)
                        Text(cap.path)
                            .monoFont(size: 11)
                            .foregroundStyle(GatewayTheme.text)
                            .lineLimit(1)
                        Spacer()
                        Text("\(cap.respStatus)")
                            .monoFont(size: 10)
                            .foregroundStyle(GatewayTheme.statusColor(cap.respStatus))
                        // AI analyze single capture button
                        if let onAnalyze = onAnalyze {
                            Button {
                                onAnalyze(cap)
                            } label: {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .font(.system(size: 12))
                                    .foregroundStyle(GatewayTheme.accent.opacity(0.7))
                                    .frame(width: 28, height: 28)
                            }
                            .accessibilityLabel("AI analyze \(cap.method) \(cap.path)")
                        }
                    }
                    Text(cap.host)
                        .monoFont(size: 9)
                        .foregroundStyle(GatewayTheme.textFaint)
                }
                .padding(.vertical, GatewayTheme.spacing(1))
                if cap.id != captures.prefix(10).last?.id {
                    Divider().background(GatewayTheme.border)
                }
            }
            if captures.count > 10 {
                Text("+ \(captures.count - 10) more")
                    .monoFont(size: 10)
                    .foregroundStyle(GatewayTheme.textFaint)
            }
        }
        .padding(GatewayTheme.spacing(3))
        .cardSurface()
    }
}

// MARK: - Replay Report View

struct ReplayReportView: View {
    let report: ReplayReport

    var body: some View {
        VStack(alignment: .leading, spacing: GatewayTheme.spacing(4)) {
            VStack(alignment: .leading, spacing: GatewayTheme.spacing(1.5)) {
                Text("REPLAY REPORT")
                    .monoFont(size: 12, weight: .heavy)
                    .foregroundStyle(GatewayTheme.cyan)
                    .kerning(1.2)
                HStack(spacing: GatewayTheme.spacing(3)) {
                    Text("\(report.succeeded) ok")
                        .monoFont(size: 12, weight: .bold)
                        .foregroundStyle(GatewayTheme.ok)
                    if report.failed > 0 {
                        Text("\(report.failed) failed")
                            .monoFont(size: 12, weight: .bold)
                            .foregroundStyle(GatewayTheme.danger)
                    }
                    Text("\(report.total) total")
                        .monoFont(size: 12)
                        .foregroundStyle(GatewayTheme.textDim)
                }
            }

            if !report.extractedTokens.isEmpty {
                VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
                    HStack(spacing: GatewayTheme.spacing(1.5)) {
                        Image(systemName: "shield.exclamation").font(.system(size: 11)).foregroundStyle(GatewayTheme.warn)
                        Text("EXTRACTED TOKENS")
                            .monoFont(size: 10, weight: .heavy)
                            .foregroundStyle(GatewayTheme.warn)
                            .kerning(1)
                    }
                    ForEach(report.extractedTokens.indices, id: \.self) { i in
                        Text(report.extractedTokens[i])
                            .monoFont(size: 11)
                            .foregroundStyle(GatewayTheme.warn)
                            .lineLimit(2)
                            .padding(.vertical, GatewayTheme.spacing(1))
                    }
                }
                .padding(GatewayTheme.spacing(3))
                .background(GatewayTheme.warn.opacity(0.08))
                .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusMd).stroke(GatewayTheme.warn.opacity(0.2), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: GatewayTheme.spacing(2)) {
                Text("FLOW SUMMARY")
                    .monoFont(size: 10, weight: .heavy)
                    .foregroundStyle(GatewayTheme.textFaint)
                    .kerning(1)
                Text(report.flowSummary)
                    .monoFont(size: 11)
                    .foregroundStyle(GatewayTheme.textDim)
                    .lineSpacing(4)
            }
            .padding(GatewayTheme.spacing(3))
            .cardSurface()

            VStack(alignment: .leading, spacing: GatewayTheme.spacing(1)) {
                Text("REQUEST LOG")
                    .monoFont(size: 10, weight: .heavy)
                    .foregroundStyle(GatewayTheme.textFaint)
                    .kerning(1)
                ForEach(report.entries, id: \.index) { entry in
                    VStack(alignment: .leading, spacing: GatewayTheme.spacing(1)) {
                        HStack(spacing: GatewayTheme.spacing(2)) {
                            Text(entry.method)
                                .monoFont(size: 10, weight: .heavy)
                                .foregroundStyle(entry.status >= 400 || entry.status == 0 ? GatewayTheme.danger : GatewayTheme.ok)
                            Text("\(entry.status)")
                                .monoFont(size: 10)
                                .foregroundStyle(GatewayTheme.textDim)
                            Text("\(entry.latencyMs)ms")
                                .monoFont(size: 10)
                                .foregroundStyle(GatewayTheme.textFaint)
                        }
                        Text(entry.url)
                            .monoFont(size: 10)
                            .foregroundStyle(GatewayTheme.textDim)
                            .lineLimit(1)
                        if let err = entry.error {
                            Text(err)
                                .monoFont(size: 10)
                                .foregroundStyle(GatewayTheme.danger)
                        }
                        if let redirect = entry.redirectUrl {
                            Text("→ \(redirect)")
                                .monoFont(size: 10)
                                .foregroundStyle(GatewayTheme.cyan)
                        }
                        if !entry.cookies.isEmpty {
                            Text("\(entry.cookies.count) cookie(s)")
                                .monoFont(size: 10)
                                .foregroundStyle(GatewayTheme.warn)
                        }
                    }
                    .padding(.horizontal, GatewayTheme.spacing(3))
                    .padding(.vertical, GatewayTheme.spacing(2))
                    .background(GatewayTheme.surface)
                    .clipShape(.rect(cornerRadius: GatewayTheme.radiusSm))
                    .overlay(RoundedRectangle(cornerRadius: GatewayTheme.radiusSm).stroke(GatewayTheme.border, lineWidth: 1))
                }
            }
        }
    }
}
