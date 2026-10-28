import PhotosUI
import SmartEntry
import SwiftUI
import UIKit
import Vision

struct AddSpottingView: View {
    @EnvironmentObject var spottingStore: SpottingStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var catalog: AviationCatalogUIService
    @Environment(\.dismiss) private var dismiss

    @StateObject private var editor = SpottingEditorModel()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosData: [Data] = []
    @State private var isDateFromPhoto = false
    @State private var isProcessingImage = false

    private let textDetector = AircraftTextDetector()

    private var canSave: Bool {
        editor.canSave(photoCount: photosData.count)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                        if photosData.isEmpty {
                            Label("Add Photos", systemImage: "camera")
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(photosData.enumerated()), id: \.offset) { index, data in
                                        if let uiImage = UIImage(data: data) {
                                            ZStack(alignment: .topTrailing) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 180, height: 200)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                                
                                                Button {
                                                    withAnimation {
                                                        photosData.remove(at: index)
                                                        if index < selectedPhotos.count {
                                                            selectedPhotos.remove(at: index)
                                                        }
                                                    }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.title2)
                                                        .foregroundStyle(.white)
                                                        .background(Circle().fill(.black.opacity(0.6)))
                                                }
                                                .padding(8)
                                            }
                                        }
                                    }
                                    
                                    // Add more photos button
                                    VStack {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 40))
                                            .foregroundStyle(appSettings.accentColor)
                                        Text("Add More")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 180, height: 200)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(height: 210)
                        }
                    }
                    .onChange(of: selectedPhotos) { _, newPhotos in
                        Task { @MainActor in
                            guard !isProcessingImage else { return }
                            isProcessingImage = true
                            
                            defer { isProcessingImage = false }
                            
                            // Clear existing photos when new selection is made
                            photosData.removeAll()
                            
                            for photo in newPhotos {
                                if let data = try? await photo.loadTransferable(type: Data.self) {
                                    // Compress image data immediately to prevent memory issues
                                    let compressedData = SpottingStore.compressImageData(data)
                                    photosData.append(compressedData)
                                    
                                    // Extract metadata from first photo only
                                    if photosData.count == 1 {
                                        if let photoDate = PhotoMetadataExtractor.extractDateFromPhoto(data) {
                                            editor.timestamp = photoDate
                                            isDateFromPhoto = true
                                        } else {
                                            isDateFromPhoto = false
                                        }
                                        
                                        // Use compressed data for detection to reduce memory usage
                                        if let uiImage = UIImage(data: compressedData) {
                                            await detectAircraftInfoFromImage(uiImage)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section("Aircraft") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Registration", text: Binding(
                            get: { editor.registration },
                            set: { editor.editRegistration($0) }
                        ))
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("registration-field")

                        if editor.registrationFromPhoto {
                            photoHint("Registration detected from photo")
                        }
                    }
                }

                SpottingReferenceForm(editor: editor, catalog: catalog, accent: appSettings.accentColor)

                Section("Notes") {
                    TextField("Additional notes...", text: $editor.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("notes-field")
                }

                Section("Date & Time") {
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker("Date Spotted", selection: $editor.timestamp, displayedComponents: [.date, .hourAndMinute])
                            .onChange(of: editor.timestamp) { _, _ in
                                isDateFromPhoto = false
                            }

                        if isDateFromPhoto {
                            photoHint("Date automatically set from photo")
                        }
                    }
                }
            }
            .navigationTitle("Add Aircraft")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: seedPhotoIfRequested)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSpotting()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("save-spotting")
                    .foregroundStyle(canSave ? appSettings.accentColor : .secondary)
                }
            }
        }
    }
    
    private func saveSpotting() {
        guard !photosData.isEmpty else {
            print("Error: Cannot save entry without photos")
            return
        }
        
        let entry = editor.entry(id: UUID(), photos: photosData)
        
        Task { @MainActor in
            spottingStore.addEntry(entry)
            dismiss()
        }
    }
    
    private func detectAircraftInfoFromImage(_ image: UIImage) async {
        await withCheckedContinuation { continuation in
            textDetector.detectAircraftInfo(in: image) { result in
                Task { @MainActor in
                    guard !Task.isCancelled else {
                        continuation.resume()
                        return
                    }
                    
                    editor.applyPhotoDetection(
                        registration: result.registration,
                        airline: result.airline,
                        confidence: Double(result.confidence)
                    )

                    continuation.resume()
                }
            }
        }
    }
    
    private func photoHint(_ text: String) -> some View {
        HStack {
            Image(systemName: "camera.fill")
                .foregroundStyle(appSettings.accentColor)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: min(maxDimension, size.width), height: min(maxDimension, size.width) / aspectRatio)
        } else {
            newSize = CGSize(width: min(maxDimension, size.height) * aspectRatio, height: min(maxDimension, size.height))
        }
        
        if newSize.width < size.width || newSize.height < size.height {
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resizedImage ?? image
        }
        
        return image
    }

    /// UI tests cannot drive the system photo picker reliably. A debug launch
    /// argument supplies one photo so the rest of the form can be saved.
    private func seedPhotoIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-UITestSeedPhoto"), photosData.isEmpty else { return }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        if let data = image.jpegData(compressionQuality: 0.8) {
            photosData = [data]
        }
        #endif
    }
}

#Preview {
    AddSpottingView()
        .environmentObject(SpottingStore())
        .environmentObject(AppSettings())
        .environmentObject(AviationCatalogUIService())
}
