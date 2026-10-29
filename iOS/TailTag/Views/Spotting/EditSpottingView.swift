import PhotosUI
import SmartEntry
import SwiftUI
import Vision

struct EditSpottingView: View {
    @EnvironmentObject var spottingStore: SpottingStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var catalog: AviationCatalogUIService
    @Environment(\.dismiss) private var dismiss

    let spotting: SpottingEntry

    @StateObject private var editor: SpottingEditorModel
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosData: [Data]
    @State private var showingDeleteAlert = false
    @State private var isDateFromPhoto = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    private let textDetector = AircraftTextDetector()

    init(spotting: SpottingEntry) {
        self.spotting = spotting
        _photosData = State(wrappedValue: spotting.photos)
        _editor = StateObject(wrappedValue: SpottingEditorModel(entry: spotting))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    photoGalleryView
                }
                
                Section("Aircraft") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "number")
                                .foregroundColor(appSettings.accentColor)
                                .frame(width: 25)
                            TextField("Registration", text: Binding(
                                get: { editor.registration },
                                set: { editor.editRegistration($0) }
                            ))
                            .accessibilityIdentifier("registration-field")
                        }
                        if editor.registrationFromPhoto {
                            photoHint("Registration detected from photo")
                        }
                    }
                }

                SpottingReferenceForm(editor: editor, catalog: catalog, accent: appSettings.accentColor)

                Section("Notes") {
                    HStack(alignment: .top) {
                        Image(systemName: "note.text")
                            .foregroundColor(appSettings.accentColor)
                            .frame(width: 25)
                            .padding(.top, 8)
                        TextField("Notes (Optional)", text: $editor.notes, axis: .vertical)
                            .lineLimit(3...6)
                            .accessibilityIdentifier("notes-field")
                    }
                }

                Section("Date & Time") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(appSettings.accentColor)
                                .frame(width: 25)
                            DatePicker("Date Spotted", selection: $editor.timestamp, displayedComponents: [.date, .hourAndMinute])
                                .onChange(of: editor.timestamp) { _, _ in
                                    isDateFromPhoto = false
                                }
                        }
                        if isDateFromPhoto {
                            photoHint("Date automatically set from photo")
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Spotting")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Saving" : "Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValidEntry || isSaving)
                    .accessibilityIdentifier("save-spotting")
                }
            }
            .alert("Could Not Save", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: selectedPhotos) { _, newPhotos in
            Task { @MainActor in
                guard !newPhotos.isEmpty else { return }
                
                for photo in newPhotos {
                    if let data = try? await photo.loadTransferable(type: Data.self) {
                        // Compress image before storing to prevent memory issues
                        let compressedData = SpottingStore.compressImageData(data)
                        photosData.append(compressedData)
                        
                        // Extract metadata from first added photo
                        if photosData.count == 1 {
                            if let photoDate = PhotoMetadataExtractor.extractDateFromPhoto(data) {
                                editor.timestamp = photoDate
                                isDateFromPhoto = true
                            } else {
                                isDateFromPhoto = false
                            }
                            
                            // Detect aircraft information from photo using compressed version
                            if let uiImage = UIImage(data: compressedData) {
                                detectAircraftInfoFromImage(uiImage)
                            }
                        }
                    }
                }
                
                // Clear selection after processing
                selectedPhotos.removeAll()
            }
        }
        .alert("Delete Spotting", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSpotting()
            }
        } message: {
            Text("This will permanently delete this spotting. This action cannot be undone.")
        }
    }
    
    private var isValidEntry: Bool {
        editor.canSave(photoCount: photosData.count)
    }

    private func saveChanges() {
        guard !isSaving else { return }
        guard !photosData.isEmpty else {
            saveErrorMessage = "Keep at least one photo before saving."
            return
        }
        let updatedSpotting = editor.entry(id: spotting.id, photos: photosData)
        isSaving = true
        do {
            try spottingStore.updateSpotting(updatedSpotting)
            dismiss()
        } catch {
            isSaving = false
            saveErrorMessage = error.localizedDescription
        }
    }
    
    private func deleteSpotting() {
        guard !isSaving else { return }
        isSaving = true
        do {
            try spottingStore.deleteSpotting(spotting)
            dismiss()
        } catch {
            isSaving = false
            saveErrorMessage = error.localizedDescription
        }
    }
    
    private func detectAircraftInfoFromImage(_ image: UIImage) {
        textDetector.detectAircraftInfo(in: image) { result in
            DispatchQueue.main.async {
                self.editor.applyPhotoDetection(
                    registration: result.registration,
                    airline: result.airline,
                    confidence: Double(result.confidence)
                )
            }
        }
    }

    private func photoHint(_ text: String) -> some View {
        HStack {
            Image(systemName: "camera.fill")
                .foregroundStyle(appSettings.accentColor)
                .font(.caption)
                .frame(width: 25)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Photo Gallery View
    private var photoGalleryView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(photosData.enumerated()), id: \.offset) { index, data in
                    photoThumbnailView(data: data, index: index)
                }
                
                addMorePhotosButton
            }
            .padding(.vertical, 4)
        }
    }
    
    private func photoThumbnailView(data: Data, index: Int) -> some View {
        Group {
            if let uiImage = UIImage(data: data) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    if photosData.count > 1 {
                        deletePhotoButton(at: index)
                    }
                }
            }
        }
    }
    
    private func deletePhotoButton(at index: Int) -> some View {
        Button {
            withAnimation {
                let _ = photosData.remove(at: index)
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .background(Circle().fill(.black.opacity(0.6)))
        }
        .padding(6)
    }
    
    private var addMorePhotosButton: some View {
        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
            VStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(appSettings.accentColor)
                Text("Add")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 120, height: 120)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

