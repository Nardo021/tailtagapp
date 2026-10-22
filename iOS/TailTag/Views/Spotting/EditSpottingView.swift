import SwiftUI
import PhotosUI
import Vision

struct EditSpottingView: View {
    @EnvironmentObject var spottingStore: SpottingStore
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    let spotting: SpottingEntry
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosData: [Data]
    @State private var registration: String
    @State private var airline: String
    @State private var location: String
    @State private var aircraftType: String
    @State private var notes: String
    @State private var timestamp: Date
    @State private var showingDeleteAlert = false
    @State private var isDateFromPhoto = false
    @State private var isRegistrationFromPhoto = false
    @State private var isAirlineFromPhoto = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    
    private let textDetector = AircraftTextDetector()
    
    init(spotting: SpottingEntry) {
        self.spotting = spotting
        _photosData = State(wrappedValue: spotting.photos)
        _registration = State(initialValue: spotting.registration)
        _airline = State(initialValue: spotting.airline)
        _location = State(initialValue: spotting.location)
        _aircraftType = State(initialValue: spotting.aircraftType ?? "")
        _notes = State(initialValue: spotting.notes ?? "")
        _timestamp = State(initialValue: spotting.timestamp)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Photos") {
                    photoGalleryView
                }
                
                Section("Aircraft Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "number")
                                .foregroundColor(appSettings.accentColor)
                                .frame(width: 25)
                            TextField("Registration", text: $registration)
                                .onChange(of: registration) { _, _ in
                                    isRegistrationFromPhoto = false
                                }
                        }
                        
                        if isRegistrationFromPhoto {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(appSettings.accentColor)
                                    .font(.caption)
                                    .frame(width: 25)
                                Text("Registration detected from photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "airplane")
                                .foregroundColor(appSettings.accentColor)
                                .frame(width: 25)
                            TextField("Airline", text: $airline)
                                .onChange(of: airline) { _, _ in
                                    isAirlineFromPhoto = false
                                }
                        }
                        
                        if isAirlineFromPhoto {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(appSettings.accentColor)
                                    .font(.caption)
                                    .frame(width: 25)
                                Text("Airline detected from photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    HStack {
                        Image(systemName: "location")
                            .foregroundColor(appSettings.accentColor)
                            .frame(width: 25)
                        TextField("Location", text: $location)
                    }
                    
                    HStack {
                        Image(systemName: "airplane.circle")
                            .foregroundColor(appSettings.accentColor)
                            .frame(width: 25)
                        TextField("Aircraft Type (Optional)", text: $aircraftType)
                    }
                }
                
                Section("Additional Info") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(appSettings.accentColor)
                                .frame(width: 25)
                            DatePicker("Date Spotted", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                                .onChange(of: timestamp) { _, _ in
                                    isDateFromPhoto = false
                                }
                        }
                        
                        if isDateFromPhoto {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(appSettings.accentColor)
                                    .font(.caption)
                                    .frame(width: 25)
                                Text("Date automatically set from photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    HStack(alignment: .top) {
                        Image(systemName: "note.text")
                            .foregroundColor(appSettings.accentColor)
                            .frame(width: 25)
                            .padding(.top, 8)
                        TextField("Notes (Optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
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
                                timestamp = photoDate
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
        !registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !airline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveChanges() {
        guard !isSaving else { return }
        guard !photosData.isEmpty else {
            saveErrorMessage = "Keep at least one photo before saving."
            return
        }
        var updatedSpotting = spotting
        updatedSpotting.photos = photosData
        updatedSpotting.registration = registration.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSpotting.airline = airline.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSpotting.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSpotting.aircraftType = aircraftType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : aircraftType.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSpotting.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSpotting.timestamp = timestamp
        
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
                // Auto-fill registration if detected and current field is empty or matches original
                if let detectedRegistration = result.registration,
                   result.confidence > 0.6,
                   (self.registration.isEmpty || self.registration == self.spotting.registration) {
                    self.registration = detectedRegistration
                    self.isRegistrationFromPhoto = true
                }
                
                // Auto-fill airline if detected and current field is empty or matches original
                if let detectedAirline = result.airline,
                   result.confidence > 0.6,
                   (self.airline.isEmpty || self.airline == self.spotting.airline) {
                    self.airline = detectedAirline
                    self.isAirlineFromPhoto = true
                }
            }
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

