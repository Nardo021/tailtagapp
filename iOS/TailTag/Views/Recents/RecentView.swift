import SwiftUI

struct RecentView: View {
    @EnvironmentObject var spottingStore: SpottingStore
    @EnvironmentObject var appSettings: AppSettings
    @State private var showingAddView = false
    @State private var selectedSortOption: SortOption = .dateNewest
    // ...existing code...
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if spottingStore.entries.isEmpty {
                    EmptyStateView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            HStack {
                                Text("Aircraft")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                Text(selectedSortOption.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            
                            ForEach(spottingStore.sortedEntries(by: selectedSortOption)) { entry in
                                SpottingCardView(entry: entry)
                            }
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("TailTag")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $selectedSortOption) {
                            ForEach(SortOption.allCases) { option in
                                Label(option.rawValue, systemImage: option.icon)
                                    .tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddView = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Aircraft")
                    .accessibilityIdentifier("add-aircraft")
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingAddView) {
            AddSpottingView()
        }
    }
}
