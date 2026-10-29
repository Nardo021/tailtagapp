# TailTag

TailTag is a native aircraft-spotting logbook for iOS and Android. Record aircraft sightings with photos, registration, airline, location, aircraft type, notes, and the date and time of the sighting.

All spotting data is stored locally on the device. There is currently no backend or account system.

## Features

- Add, edit, delete, and browse aircraft sightings
- Capture or select one or more aircraft photos
- Search, sort, and filter a saved spotting collection by operator, manufacturer, aircraft, role, operation, location, registration, and date
- Extract aircraft registration text from photos with on-device OCR
- Search the bundled catalog for an operator, manufacturer, aircraft model or family, and airport, or enter custom text
- Record aircraft role and operation type separately
- Store optional aircraft details, location, and notes
- Customize accent color and light/dark appearance
- iOS Spotlight search and App Intents integration

## Repository layout

```text
.
├── Android/          # Android Studio / Gradle project
├── data/aviation/    # Authoritative offline aviation catalog
├── docs/             # Catalog and data-source notes
├── iOS/              # Xcode project, AviationCatalogCore, and SmartEntryCore
├── scripts/aviation/ # Catalog fetch, build, and validation
└── README.md
```

The two apps share the same product and user-facing concepts, but are implemented independently with each platform's native UI and storage APIs. The aviation reference catalog is generated once and bundled into both apps. See `docs/aviation-catalog.md`. The spotting form that searches that catalog is described in `docs/smart-entry.md`. Filtering a saved collection is described in `docs/advanced-filters.md`.

## iOS

### Technology

- Swift and SwiftUI
- Core Data for local spotting data and photos
- PhotosUI for photo selection
- App Intents and Spotlight indexing
- Deployment target: iOS 18.0 or later

### Requirements

- macOS
- Xcode with support for the project's Swift and iOS SDK versions
- An iOS 18 or later simulator, or a physical iPhone running iOS 18 or later

### Open and run

1. Open `iOS/TailTag.xcodeproj` in Xcode.
2. Select the `TailTag` target and an iOS simulator or connected device.
3. If Xcode asks for a signing team, open the target's **Signing & Capabilities** settings and select your Apple Developer team.
4. Press **Run**.

The iOS app's bundle identifier is currently `com.Josh.TailTag`. Change it if you need to install a separate app with your own identifier.

## Android

### Technology

- Kotlin
- Jetpack Compose and Material 3
- AndroidX Navigation and Lifecycle
- Google ML Kit text recognition
- Local storage with SharedPreferences and app-private photo files
- Minimum Android version: API 26
- Compile and target SDK: API 37

### Requirements

- Android Studio with support for the Android Gradle Plugin used by this project
- JDK 17 or later
- Android SDK Platform 37, or allow Android Studio/Gradle to install it
- An Android API 26 or later emulator, or a connected Android device

### Open and run

1. Open the `Android/` directory in Android Studio.
2. Let Gradle sync and install any requested SDK components.
3. Select the `app` configuration and an emulator or connected device.
4. Press **Run**.

From a terminal, the main build and test commands are:

```bash
cd Android
./gradlew assembleDebug
./gradlew test
```

For instrumented tests on a running emulator or connected device:

```bash
./gradlew connectedAndroidTest
```

On Windows, use `gradlew.bat` instead of `./gradlew`.

`Android/local.properties` is generated for each developer's machine and must not be committed. Build outputs, APKs, signing files, IDE metadata, and other machine-specific files are excluded by the repository `.gitignore`.

## Aviation reference catalog

Operators, aircraft manufacturers and models, airports, and classification terms are bundled for offline search. Application builds do not download catalog data. To rebuild from the pinned snapshots:

```bash
python3 scripts/aviation/build_catalog.py
python3 scripts/aviation/validate_catalog.py
```

Refreshing the snapshots is a separate step and needs network access. The command and the license limits are described in `docs/aviation-data-sources.md`.
