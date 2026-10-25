//
//  SpottingDetailView.swift
//  TailTag
//
//  Created by Josh Mansfield on 25/06/2025.
//

import AppIntents
import SmartEntry
import SwiftUI

struct SpottingDetailView: View {
    let entry: SpottingEntry
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var spottingStore: SpottingStore
    @EnvironmentObject var catalog: AviationCatalogUIService
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditView = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Photo Gallery with TabView
                    TabView {
                        ForEach(Array(entry.photos.enumerated()), id: \.offset) { index, photoData in
                            if let uiImage = UIImage(data: photoData), !photoData.isEmpty {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                // Placeholder with gradient
                                LinearGradient(
                                    colors: [appSettings.accentColor.opacity(0.3), appSettings.accentColor.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(height: 200)
                                .overlay {
                                    Image(systemName: "airplane")
                                        .font(.system(size: 60))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 320)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Details List
                    VStack(spacing: 0) {
                        // Registration
                        DetailRowView(
                            icon: "airplane",
                            title: "Registration",
                            value: entry.registration,
                            iconColor: appSettings.accentColor
                        )
                        
                        Divider()
                            .padding(.leading, 60)
                        
                        // Airline
                        DetailRowView(
                            icon: "building.2",
                            title: "Airline / Operator",
                            value: selectionSummary(reference.operatorField, emptyPlaceholder: "No operator"),
                            caption: selectionCaption(reference.operatorField),
                            iconColor: appSettings.accentColor
                        )

                        if reference.manufacturerField.kind != .absent {
                            Divider().padding(.leading, 60)
                            DetailRowView(
                                icon: "wrench.and.screwdriver",
                                title: "Manufacturer",
                                value: selectionSummary(reference.manufacturerField, emptyPlaceholder: "No manufacturer"),
                                caption: selectionCaption(reference.manufacturerField),
                                iconColor: appSettings.accentColor
                            )
                        }

                        Divider().padding(.leading, 60)

                        DetailRowView(
                            icon: "location",
                            title: "Location",
                            value: selectionSummary(reference.locationField, emptyPlaceholder: entry.location),
                            caption: selectionCaption(reference.locationField),
                            iconColor: appSettings.accentColor
                        )

                        if reference.aircraftField.kind != .absent {
                            Divider().padding(.leading, 60)
                            DetailRowView(
                                icon: "airplane.departure",
                                title: "Aircraft",
                                value: selectionSummary(reference.aircraftField, emptyPlaceholder: "No aircraft"),
                                caption: selectionCaption(reference.aircraftField),
                                iconColor: appSettings.accentColor
                            )
                        }

                        if let role = classificationSummary(
                            id: reference.classification.roleId,
                            note: reference.classification.roleNote,
                            labels: mergedRoleLabels
                        ) {
                            Divider().padding(.leading, 60)
                            DetailRowView(
                                icon: "tag",
                                title: "Aircraft role",
                                value: role,
                                iconColor: appSettings.accentColor
                            )
                        }

                        if let operation = classificationSummary(
                            id: reference.classification.operationTypeId,
                            note: reference.classification.operationTypeNote,
                            labels: mergedOperationLabels
                        ) {
                            Divider().padding(.leading, 60)
                            DetailRowView(
                                icon: "arrow.triangle.branch",
                                title: "Operation",
                                value: operation,
                                iconColor: appSettings.accentColor
                            )
                        }
                        
                        Divider()
                            .padding(.leading, 60)
                        
                        // Date & Time
                        DetailRowView(
                            icon: "calendar",
                            title: "Spotted",
                            value: DateFormatter.spottingDetail.string(from: entry.timestamp),
                            iconColor: appSettings.accentColor
                        )
                        
                        if let notes = entry.notes, !notes.isEmpty {
                            Divider()
                                .padding(.leading, 60)
                            
                            DetailRowView(
                                icon: "note.text",
                                title: "Notes",
                                value: notes,
                                iconColor: appSettings.accentColor,
                                isMultiline: true
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Aircraft Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingEditView = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("spotting-actions")
                    .accessibilityLabel("Spotting actions")
                }
            }
        }
        .sheet(isPresented: $showingEditView) {
            EditSpottingView(spotting: entry)
        }
        .alert("Delete Spotting", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                spottingStore.deleteSpotting(entry)
                dismiss()
            }
        } message: {
            Text("This will permanently delete this spotting. This action cannot be undone.")
        }
        .userActivity("com.Josh.TailTag.viewingSpotting", element: TailTagSpottingEntity(entry: entry)) { spottingEntity, activity in
            activity.title = "Viewing \(entry.registration)"
            if #available(iOS 18.2, *) {
                activity.appEntityIdentifier = EntityIdentifier(for: spottingEntity)
            }
        }
    }

    private var reference: SpottingReferenceState {
        var copy = entry.reference
        copy.operatorField = copy.operatorField.reconciled(existsInCatalog: catalog.operatorExists(copy.operatorField.catalogId))
        copy.manufacturerField = copy.manufacturerField.reconciled(existsInCatalog: catalog.manufacturerExists(copy.manufacturerField.catalogId))
        copy.aircraftField = copy.aircraftField.reconciled(existsInCatalog: catalog.aircraftExists(copy.aircraftField.catalogId))
        copy.locationField = copy.locationField.reconciled(existsInCatalog: catalog.airportExists(copy.locationField.catalogId))
        return copy
    }

    private var mergedRoleLabels: [String: String] {
        ClassificationCopy.roleLabels.merging(catalog.classificationLabels().roles) { _, catalogLabel in catalogLabel }
    }

    private var mergedOperationLabels: [String: String] {
        ClassificationCopy.operationLabels.merging(catalog.classificationLabels().operations) { _, catalogLabel in catalogLabel }
    }
}

struct DetailRowView: View {
    let icon: String
    let title: String
    let value: String
    var caption: String? = nil
    let iconColor: Color
    var isMultiline: Bool = false

    var body: some View {
        HStack(alignment: isMultiline ? .top : .center, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)
                .padding(.top, isMultiline ? 2 : 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)

                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
