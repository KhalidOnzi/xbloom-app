import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedBrew.createdAt, order: .reverse) private var brews: [SavedBrew]

    var body: some View {
        Group {
            if brews.isEmpty {
                ContentUnavailableView(
                    "No bags yet",
                    systemImage: "book.closed",
                    description: Text("Recipes you generate or push will land here.")
                )
            } else {
                List {
                    ForEach(brews) { brew in
                        Button {
                            model.load(saved: brew)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(brew.coffeeName)
                                    .font(.headline)
                                    .foregroundStyle(BloomTheme.ink)
                                if !brew.subtitle.isEmpty {
                                    Text(brew.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(BloomTheme.muted)
                                }
                                HStack {
                                    Text(brew.createdAt, style: .date)
                                    if brew.pushedAt != nil {
                                        Text("In xBloom")
                                            .foregroundStyle(BloomTheme.moss)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(BloomTheme.muted)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .bloomBackground()
        .navigationTitle("History")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(brews[index])
        }
        try? context.save()
    }
}
