import AppIntents
import AviationCatalog
import SwiftUI
import SwiftData

@main
struct TailTagApp: App {
    @StateObject private var spottingStore = SpottingStore()
    @StateObject private var appSettings = AppSettings()
    @StateObject private var intentRouter = TailTagIntentRouter()
    @StateObject private var catalogService = AviationCatalogUIService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(ModelContainer.tailTag)
                .environmentObject(spottingStore)
                .environmentObject(appSettings)
                .environmentObject(intentRouter)
                .environmentObject(catalogService)
                .task {
                    catalogService.prepare()
                    // CoreData → SwiftData (runs once, local store)
                    await SpottingMigrator.migrateIfNeeded(store: spottingStore)
                    // Local SwiftData → CloudKit store (runs once when sync is first enabled)
                    await SpottingMigrator.migrateToCloudKitIfNeeded(store: spottingStore)

                    TailTagShortcutsProvider.updateAppShortcutParameters()
                    if AviationCatalogBridge.supportedSchemaVersion != AviationCatalogLoader.supportedSchemaVersion {
                        print("Aviation catalog schema is unavailable")
                    }
                    do {
                        try await TailTagSpotlightIndexer.indexAllSpottingEntries()
                    } catch {
                        print("Spotlight indexing failed: \(error.localizedDescription)")
                    }
                }
        }
    }
}

enum ActiveStoreIdentity: Equatable, Sendable {
    /// The container was opened with the private CloudKit database. A later local save is not a completed upload.
    case cloudKit(storeURL: URL)
    /// On-device store. `cloudKitFallback` means the iCloud preference was on but the CloudKit store did not open.
    case local(storeURL: URL, cloudKitFallback: Bool)
}

extension ModelContainer {
    // Shared container used by the app and AppIntents.
    // Reads the iCloud sync preference at startup; toggling requires a restart.
    static let tailTag: ModelContainer = {
        let schema = Schema([SpottingRecord.self, PhotoRecord.self])
        let iCloudEnabled = UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncKey)

        if iCloudEnabled {
            do {
                // Use a distinct store name so this file is never opened without CloudKit —
                // opening a local-only store with CloudKit enabled causes SwiftDataError 1.
                let config = ModelConfiguration(
                    "TailTagSync",
                    schema: schema,
                    cloudKitDatabase: .private("iCloud.com.Josh.TailTag")
                )
                let container = try ModelContainer(for: schema, configurations: [config])
                activeIdentity = .cloudKit(storeURL: config.url)
                return container
            } catch {
                cloudKitFallback = true
            }
        }

        do {
            // Local store keeps its own file so it can never conflict with the CloudKit store.
            let config = ModelConfiguration("TailTagLocal", schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            activeIdentity = .local(storeURL: config.url, cloudKitFallback: cloudKitFallback)
            return container
        } catch {
            fatalError("Cannot create local ModelContainer: \(error)")
        }
    }()

    /// Set while `tailTag` is created. Tests that never touch `tailTag` leave this as local.
    static var activeIdentity: ActiveStoreIdentity = .local(storeURL: URL(fileURLWithPath: "/dev/null"), cloudKitFallback: false)
    static var cloudKitFallback = false
}
