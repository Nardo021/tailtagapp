//
//  SpottingCardView.swift
//  TailTag
//
//  Created by Josh Mansfield on 25/06/2025.
//

import SwiftUI

struct SpottingCardView: View {
    let entry: SpottingEntry
    @EnvironmentObject var appSettings: AppSettings
    @State private var showingDetail = false
    
    var body: some View {
        Button {
            showingDetail = true
        } label: {
            ZStack {
                // Background Image (First Photo)
                if let firstPhoto = entry.photos.first,
                   let uiImage = UIImage(data: firstPhoto), !firstPhoto.isEmpty {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
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
                }
                
                // Aircraft Type Overlay (Top Right)
                VStack {
                    HStack {
                        Spacer()
                        
                        HStack(spacing: 8) {
                            // Photo count badge
                            if entry.photos.count > 1 {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.stack.fill")
                                        .font(.subheadline)
                                    Text("\(entry.photos.count)")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            // Aircraft type
                            if let aircraftType = entry.aircraftType {
                                Text(aircraftType)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.black.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 16)
                    }
                    Spacer()
                }
                
                // Registration and Airline Overlay (Bottom)
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.registration)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            
                            Text(entry.airline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No operator" : entry.airline)
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.9))
                            
                            Text(DateFormatter.spottingCard.string(from: entry.timestamp))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("spotting-card-\(entry.registration)")
        .sheet(isPresented: $showingDetail) {
            SpottingDetailView(entry: entry)
        }
    }
}


