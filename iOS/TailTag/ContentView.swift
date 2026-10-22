import SwiftUI

enum TailTagTab {
    case recent
    case search
    case settings
}

struct ContentView: View {
    @EnvironmentObject var spottingStore: SpottingStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var intentRouter: TailTagIntentRouter
    @State private var selectedTab: TailTagTab = .recent
    @State private var searchText = ""
    @State private var selectedSpotting: SpottingEntry?
    @State private var showingAddSpotting = false

    var body: some View {
        Group {
            if appSettings.hasCompletedOnboarding {
                mainAppView
            } else {
                OnboardingView {
                    appSettings.hasCompletedOnboarding = true
                }
                .environmentObject(appSettings)
            }
        }
        .onAppear {
            openSearchIfNeeded(intentRouter.searchText)
            openSpottingIfNeeded(intentRouter.spottingIDToOpen)
            showAddSpottingIfNeeded(intentRouter.shouldShowAddSpotting)
        }
        .onReceive(intentRouter.$searchText) { searchText in
            openSearchIfNeeded(searchText)
        }
        .onReceive(intentRouter.$spottingIDToOpen) { spottingID in
            openSpottingIfNeeded(spottingID)
        }
        .onReceive(intentRouter.$shouldShowAddSpotting) { shouldShowAddSpotting in
            showAddSpottingIfNeeded(shouldShowAddSpotting)
        }
        .sheet(item: $selectedSpotting) { spotting in
            SpottingDetailView(entry: spotting)
                .environmentObject(spottingStore)
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $showingAddSpotting) {
            AddSpottingView()
                .environmentObject(spottingStore)
                .environmentObject(appSettings)
        }
        .alert("Spotting Data", isPresented: Binding(
            get: { spottingStore.userNotice != nil },
            set: { if !$0 { spottingStore.userNotice = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(spottingStore.userNotice ?? "")
        }
    }

    private var mainAppView: AnyView {
        if #available(iOS 26.0, *) {
            return AnyView(TabView(selection: $selectedTab) {
                Tab("Recent", systemImage: "clock", value: TailTagTab.recent) {
                    RecentView()
                        .environmentObject(spottingStore)
                        .environmentObject(appSettings)
                }

                Tab("Search", systemImage: "magnifyingglass", value: TailTagTab.search, role: .search) {
                    SearchView(searchText: $searchText)
                        .environmentObject(spottingStore)
                        .environmentObject(appSettings)
                }

                Tab("Settings", systemImage: "gearshape", value: TailTagTab.settings) {
                    SettingsView()
                        .environmentObject(spottingStore)
                        .environmentObject(appSettings)
                }
            }
            .accentColor(appSettings.accentColor)
            .preferredColorScheme(appSettings.colorScheme)
            .tabViewStyle(.tabBarOnly)
            .tabViewSearchActivation(.searchTabSelection)
            )

        } else {
            return AnyView(TabView(selection: $selectedTab) {
                Tab("Recent", systemImage: "clock", value: TailTagTab.recent) {
                    RecentView()
                        .environmentObject(spottingStore)
                        .environmentObject(appSettings)
                }

                Tab("Search", systemImage: "magnifyingglass", value: TailTagTab.search) {
                    SearchView(searchText: $searchText)
                        .environmentObject(spottingStore)
                        .environmentObject(appSettings)
                }

                Tab("Settings", systemImage: "gearshape", value: TailTagTab.settings) {
                    SettingsView()
                        .environmentObject(spottingStore)
                        .environmentObject(appSettings)
                }
            }
            .accentColor(appSettings.accentColor)
            .preferredColorScheme(appSettings.colorScheme)
            .tabViewStyle(.tabBarOnly)
            )
        }
    }

    private func openSearchIfNeeded(_ searchText: String?) {
        guard let searchText, !searchText.isEmpty else { return }
        self.searchText = searchText
        selectedTab = .search
        intentRouter.clearSearchRequest()
    }

    private func openSpottingIfNeeded(_ spottingID: UUID?) {
        guard let spottingID,
              let spotting = spottingStore.entries.first(where: { $0.id == spottingID }) else {
            return
        }

        selectedTab = .recent
        selectedSpotting = spotting
        intentRouter.clearSpottingOpenRequest()
    }

    private func showAddSpottingIfNeeded(_ shouldShowAddSpotting: Bool) {
        guard shouldShowAddSpotting else { return }
        selectedTab = .recent
        showingAddSpotting = true
        intentRouter.clearAddSpottingRequest()
    }
}
