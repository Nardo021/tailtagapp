import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var spottingStore: SpottingStore
    @State private var showResetConfirmation = false
    @State private var resetErrorMessage: String?
    
    var body: some View {
        Section("App") {
            Link(destination: URL(string: "mailto:joshcumulus@proton.me?subject=TailTag%20App%20Support")!) {
                HStack {
                    Image(systemName: "envelope")
                        .foregroundColor(appSettings.accentColor)
                        .frame(width: 25)
                    Text("Need Help?")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                appSettings.hasCompletedOnboarding = false
            } label: {
                HStack {
                    Image(systemName: "play.circle")
                        .foregroundColor(appSettings.accentColor)
                        .frame(width: 25)
                    Text("Replay Onboarding")
                        .foregroundColor(.primary)
                }
            }
            
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.red)
                        .frame(width: 25)
                    Text("Reset App")
                }
            }
            .alert("Reset All Settings", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetAppSettings()
                }
            } message: {
                Text("This will reset all app settings to their defaults and clear all spotting data. This action cannot be undone.")
            }
            .alert("Could Not Reset", isPresented: Binding(
                get: { resetErrorMessage != nil },
                set: { if !$0 { resetErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resetErrorMessage ?? "")
            }
        }
    }
    
    private func resetAppSettings() {
        do {
            try spottingStore.clearAllEntries()
        } catch {
            resetErrorMessage = "Spotting records could not be cleared, so settings were left unchanged."
            return
        }
        appSettings.accentColor = .blue
        appSettings.colorScheme = nil
        appSettings.currentAppIcon = nil
        appSettings.hasCompletedOnboarding = false
    }
}

#Preview {
    List {
        AppSettingsView()
            .environmentObject(AppSettings())
            .environmentObject(SpottingStore())
    }
}
