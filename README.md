# TailTag

TailTag is a native aircraft-spotting logbook for iOS and Android. Record aircraft sightings with photos, registration, airline, location, aircraft type, notes, and the date and time of the sighting.

All spotting data is stored locally on the device. There is currently no backend or account system.

## Features

- Add, edit, delete, and browse aircraft sightings
- Capture or select one or more aircraft photos
- Search and sort your spotting history
- Extract aircraft registration text from photos with on-device OCR
- Store optional aircraft details, location, and notes
- Customize accent color and light/dark appearance
- iOS Spotlight search and App Intents integration

## Repository layout

```text
.
├── Android/       # Android Studio / Gradle project
├── iOS/           # Xcode project
└── README.md
```

The two apps share the same product and user-facing concepts, but are implemented independently with each platform's native UI and storage APIs.

## iOS

### Technology

- Swift and SwiftUI
- SwiftData for spotting records, with a one-time migration from the older Core Data store
- Optional iCloud sync through a CloudKit-backed SwiftData store
- PhotosUI for photo selection
- App Intents and Spotlight indexing
- Deployment target: iOS 18.0 or later

How records, photos, and migrations are kept safe is described in [docs/data-integrity.md](docs/data-integrity.md).

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
- Local storage with SharedPreferences and app-private photo files. See [docs/data-integrity.md](docs/data-integrity.md).
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
