import SwiftUI

@main
struct EdgeGatewayDashboardApp: App {
    var body: some Scene {
        WindowGroup {
            TabNavigationView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Tab Navigation

struct TabNavigationView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardScreen()
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "gauge.with.dots.needle.33percent" : "gauge.open.with.lines.needle.33percent")
                    Text("Dashboard")
                }
                .tag(0)

            ProxiesScreen()
                .tabItem {
                    Image(systemName: "network")
                    Text("Proxies")
                }
                .tag(1)

            InterceptsScreen()
                .tabItem {
                    Image(systemName: "shield.exclamation")
                    Text("Intercepts")
                }
                .tag(2)

            ReconScreen()
                .tabItem {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("Recon")
                }
                .tag(3)

            SettingsScreen()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(4)
        }
        .tint(GatewayTheme.accent)
    }
}
