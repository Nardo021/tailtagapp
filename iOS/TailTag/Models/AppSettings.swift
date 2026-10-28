import SwiftUI
import Foundation
import Combine

class AppSettings: ObservableObject {
    @Published var accentColor: Color = .blue {
        didSet { saveAccentColor() }
    }

    @Published var colorScheme: ColorScheme? = nil {
        didSet { saveColorScheme() }
    }

    @Published var currentAppIcon: String? = nil {
        didSet { saveAppIcon() }
    }

    @Published var hasCompletedOnboarding: Bool = false {
        didSet { saveOnboardingStatus() }
    }

    @Published var iCloudSyncEnabled: Bool = false {
        didSet { saveICloudSyncSetting() }
    }

    private let userDefaults = UserDefaults.standard
    private let accentColorKey = "AccentColor"
    private let colorSchemeKey = "ColorScheme"
    private let appIconKey = "AppIcon"
    private let onboardingKey = "HasCompletedOnboarding"

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestReset") {
            userDefaults.removeObject(forKey: onboardingKey)
        }
        #endif
        loadSettings()
    }

    private func saveAccentColor() {
        if let colorOption = AccentColorOption.defaultOptions.first(where: { $0.color.description == accentColor.description }) {
            userDefaults.set(colorOption.id, forKey: accentColorKey)
        }
    }

    private func saveColorScheme() {
        if let scheme = colorScheme {
            userDefaults.set(scheme == .dark ? "dark" : "light", forKey: colorSchemeKey)
        } else {
            userDefaults.set("system", forKey: colorSchemeKey)
        }
    }

    private func saveAppIcon() {
        userDefaults.set(currentAppIcon, forKey: appIconKey)
    }

    private func saveOnboardingStatus() {
        userDefaults.set(hasCompletedOnboarding, forKey: onboardingKey)
    }

    private func saveICloudSyncSetting() {
        userDefaults.set(iCloudSyncEnabled, forKey: PersistenceController.iCloudSyncKey)
    }

    private func loadSettings() {
        if let colorId = userDefaults.string(forKey: accentColorKey),
           let colorOption = AccentColorOption.defaultOptions.first(where: { $0.id == colorId }) {
            self.accentColor = colorOption.color
        }

        let schemeString = userDefaults.string(forKey: colorSchemeKey) ?? "system"
        switch schemeString {
        case "dark":
            self.colorScheme = .dark
        case "light":
            self.colorScheme = .light
        default:
            self.colorScheme = nil
        }

        self.currentAppIcon = userDefaults.string(forKey: appIconKey)
        self.hasCompletedOnboarding = userDefaults.bool(forKey: onboardingKey)
        self.iCloudSyncEnabled = userDefaults.bool(forKey: PersistenceController.iCloudSyncKey)
    }
}

struct AccentColorOption: Identifiable {
    let id: String
    let color: Color
    let name: String
}

extension AccentColorOption {
    static let defaultOptions: [AccentColorOption] = [
        AccentColorOption(id: "blue", color: .blue, name: "Blue"),
        AccentColorOption(id: "red", color: .red, name: "Red"),
        AccentColorOption(id: "orange", color: .orange, name: "Orange"),
        AccentColorOption(id: "yellow", color: .yellow, name: "Yellow"),
        AccentColorOption(id: "green", color: .green, name: "Green"),
        AccentColorOption(id: "purple", color: .purple, name: "Purple"),
        AccentColorOption(id: "pink", color: .pink, name: "Pink"),
        AccentColorOption(id: "teal", color: .teal, name: "Teal"),
        AccentColorOption(id: "indigo", color: .indigo, name: "Indigo"),
        AccentColorOption(id: "mint", color: .mint, name: "Mint")
    ]
}

enum AppColorScheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
