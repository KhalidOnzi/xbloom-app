import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Check the bag.")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(BloomTheme.ink)
                Text("Fix anything the camera missed before we build the recipe.")
                    .foregroundStyle(BloomTheme.muted)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(BloomTheme.clay)
                        .bloomCard()
                }

                VStack(alignment: .leading, spacing: 14) {
                    field("Coffee", text: $model.profile.name)
                    field("Roaster", text: $model.profile.roaster)
                    field("Origin", text: $model.profile.origin)
                    field("Region", text: $model.profile.region)
                    field("Variety", text: $model.profile.variety)
                    Picker("Process", selection: $model.profile.process) {
                        ForEach(ProcessMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    Picker("Roast", selection: $model.profile.roast) {
                        ForEach(RoastLevel.allCases) { roast in
                            Text(roast.label).tag(roast)
                        }
                    }
                    field("Tasting notes", text: $model.profile.tastingNotes, axis: .vertical)
                    field("Roast date", text: $model.profile.roastDate)
                    field("Altitude", text: $model.profile.altitude)
                    field("Your notes", text: $model.profile.extraNotes, axis: .vertical)
                }
                .bloomCard()

                Button {
                    Task { await model.generateRecipe() }
                } label: {
                    if model.isGenerating {
                        ProgressView().tint(.white)
                    } else {
                        Label("Generate recipe", systemImage: "cup.and.saucer.fill")
                    }
                }
                .buttonStyle(BloomButtonStyle())
                .disabled(model.isGenerating)
            }
            .padding(20)
        }
        .bloomBackground()
        .navigationTitle("Coffee")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(BloomTheme.muted)
            TextField(title, text: text, axis: axis)
                .textInputAutocapitalization(.words)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
        }
    }
}
