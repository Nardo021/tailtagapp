import CloudKit
import SwiftData
import SwiftUI

struct iCloudSyncSettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @State private var showRestartAlert = false
    @State private var pendingSyncValue = false
    @State private var cloudKitStatus: CloudKitSyncStatus = .unknown

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appSettings.iCloudSyncEnabled },
                set: { newValue in
                    pendingSyncValue = newValue
                    appSettings.iCloudSyncEnabled = newValue
                    showRestartAlert = true
                }
            )) {
                HStack {
                    Image(systemName: "icloud")
                        .foregroundColor(appSettings.accentColor)
                        .frame(width: 25)
                    Text("iCloud Sync")
                }
            }

            if appSettings.iCloudSyncEnabled {
                HStack(spacing: 12) {
                    Image(systemName: cloudKitStatus.iconName)
                        .foregroundColor(cloudKitStatus.color)
                        .frame(width: 25)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cloudKitStatus.title)
                            .font(.subheadline)
                        Text(cloudKitStatus.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .task {
                    cloudKitStatus = await checkCloudKitStatus()
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(appSettings.iCloudSyncEnabled
                ? "iCloud sync uses this device's saved records after TailTag is opened again. A saved spotting is not the same as a finished upload to every device."
                : "Enable to back up and sync your spottings across all your Apple devices via iCloud.")
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pendingSyncValue
                ? "iCloud sync will be enabled the next time you open TailTag."
                : "iCloud sync will be disabled the next time you open TailTag.")
        }
    }

    private func checkCloudKitStatus() async -> CloudKitSyncStatus {
        do {
            let status = try await CKContainer(identifier: "iCloud.com.Josh.TailTag").accountStatus()
            switch status {
            case .available:
                switch ModelContainer.activeIdentity {
                case .cloudKit:
                    return .available
                case .local(_, let cloudKitFallback):
                    if cloudKitFallback {
                        return .localFallback("iCloud storage could not be opened. This launch is keeping records on this device, and they were not marked as migrated.")
                    }
                    return .localFallback("iCloud sync starts the next time TailTag is opened. An available account does not mean records have synced.")
                }
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine:
                return .unknown
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            @unknown default:
                return .unknown
            }
        } catch {
            return .containerError(error.localizedDescription)
        }
    }
}

enum CloudKitSyncStatus {
    case unknown
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case containerError(String)
    case localFallback(String)

    var iconName: String {
        switch self {
        case .available:               return "checkmark.icloud"
        case .noAccount:               return "icloud.slash"
        case .restricted:              return "lock.icloud"
        case .temporarilyUnavailable:  return "exclamationmark.icloud"
        case .containerError:          return "xmark.icloud"
        case .localFallback:           return "icloud.slash"
        case .unknown:                 return "icloud"
        }
    }

    var color: Color {
        switch self {
        case .available:               return .green
        case .noAccount, .restricted, .containerError: return .red
        case .temporarilyUnavailable, .localFallback: return .orange
        case .unknown:                 return .secondary
        }
    }

    var title: String {
        switch self {
        case .available:               return "iCloud Available"
        case .noAccount:               return "Not Signed In"
        case .restricted:              return "Restricted"
        case .temporarilyUnavailable:  return "Temporarily Unavailable"
        case .containerError:          return "Container Error"
        case .localFallback:           return "On This Device"
        case .unknown:                 return "Checking..."
        }
    }

    var detail: String {
        switch self {
        case .available:
            return "Saves stay on this device first and upload when the network allows. A save does not mean other devices already have it."
        case .localFallback(let message):
            return message
        case .noAccount:
            return "Sign in to iCloud in Settings to enable sync"
        case .restricted:
            return "iCloud access is restricted on this device"
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable — will retry automatically"
        case .containerError(let message):
            return "The iCloud container could not be reached: \(message)"
        case .unknown:
            return "Checking iCloud status..."
        }
    }
}

#Preview {
    List {
        iCloudSyncSettingsView()
            .environmentObject(AppSettings())
    }
}
