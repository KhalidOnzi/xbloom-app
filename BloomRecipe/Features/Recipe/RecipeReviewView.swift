import SwiftData
import SwiftUI

struct RecipeReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var model = model
        Group {
            if let recipe = model.recipe {
                editor(recipe: recipe)
            } else {
                ContentUnavailableView(
                    "No recipe yet",
                    systemImage: "cup.and.saucer",
                    description: Text("Generate a recipe from the coffee profile.")
                )
            }
        }
        .bloomBackground()
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $model.showPushSuccess) {
            PushSuccessView(action: model.lastPushAction ?? "added")
        }
    }

    private func editor(recipe: BloomBrewRecipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(recipe.name)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                Text(recipe.bloomPreview)
                    .foregroundStyle(BloomTheme.muted)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(BloomTheme.clay)
                        .bloomCard()
                }

                VStack(alignment: .leading, spacing: 16) {
                    stepperRow("Dose", value: recipe.doseG, range: 5...18, step: 0.5, format: String(format: "%.1f g", recipe.doseG)) { value in
                        var next = recipe
                        next.doseG = value
                        model.applyManualEdits(next)
                    }
                    stepperRow("Ratio", value: recipe.ratio, range: 13...18, step: 0.5, format: String(format: "1:%.1f", recipe.ratio)) { value in
                        var next = recipe
                        next.ratio = value
                        model.applyManualEdits(next)
                    }
                    stepperRow("Grind", value: Double(recipe.grind), range: 1...80, step: 1, format: "\(recipe.grind)") { value in
                        var next = recipe
                        next.grind = Int(value)
                        model.applyManualEdits(next)
                    }
                    stepperRow("RPM", value: Double(recipe.rpm), range: 60...120, step: 10, format: "\(recipe.rpm)") { value in
                        var next = recipe
                        next.rpm = RecipeEngine.snappedRPM(Int(value))
                        next.pours = next.pours.map { pour in
                            var copy = pour
                            copy.rpm = next.rpm
                            return copy
                        }
                        model.applyManualEdits(next)
                    }
                    LabeledContent("Water", value: "\(Int(recipe.totalWaterMl.rounded())) ml")
                }
                .bloomCard()

                VStack(alignment: .leading, spacing: 0) {
                    Text("POURS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BloomTheme.muted)
                        .padding(.bottom, 12)
                    ForEach(Array(recipe.pours.enumerated()), id: \.element.id) { index, pour in
                        PourRow(pour: pour, isLast: index == recipe.pours.count - 1) { updated in
                            var next = recipe
                            if let idx = next.pours.firstIndex(where: { $0.id == updated.id }) {
                                next.pours[idx] = updated
                            }
                            model.applyManualEdits(next)
                        }
                    }
                }
                .bloomCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("WHY THIS RECIPE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BloomTheme.muted)
                    Text(recipe.rationale)
                        .font(.body)
                        .foregroundStyle(BloomTheme.ink)
                }
                .bloomCard()

                Button {
                    Task { await model.generateRecipe() }
                } label: {
                    Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(BloomButtonStyle(filled: false))
                .disabled(model.isGenerating)

                Button {
                    Task { await model.pushToXBloom(context: context) }
                } label: {
                    if model.isPushing {
                        ProgressView().tint(.white)
                    } else {
                        Label("Create in xBloom", systemImage: "arrow.up.circle.fill")
                    }
                }
                .buttonStyle(BloomButtonStyle(tint: BloomTheme.moss))
                .disabled(model.isPushing || !model.hasXBloomCredentials)

                if !model.hasXBloomCredentials {
                    Text("Add your xBloom email and password in Settings to create the recipe in the official app.")
                        .font(.footnote)
                        .foregroundStyle(BloomTheme.muted)
                }

                Button("Save on this iPhone") {
                    model.saveLocally(context: context)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(BloomTheme.roast)
            }
            .padding(20)
        }
    }

    private func stepperRow(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        format: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        Stepper(value: Binding(
            get: { value },
            set: onChange
        ), in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text(format)
                    .foregroundStyle(BloomTheme.muted)
            }
        }
    }
}

private struct PourRow: View {
    var pour: PourStep
    var isLast: Bool
    var onChange: (PourStep) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(BloomTheme.clay)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                if !isLast {
                    Rectangle()
                        .fill(BloomTheme.clay.opacity(0.28))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(pour.name)
                        .font(.headline)
                    Spacer()
                    Text("\(Int(pour.volumeMl.rounded())) ml")
                        .font(.headline)
                }
                Text("\(pour.temperatureC) °C · \(pour.pattern.label) · \(String(format: "%.1f", pour.flowMlPerS)) ml/s")
                    .font(.caption)
                    .foregroundStyle(BloomTheme.muted)
                Text("Pause \(pour.pauseSeconds)s\(pour.agitation ? " · agitate" : "")")
                    .font(.caption)
                    .foregroundStyle(BloomTheme.muted)
                Picker("Pattern", selection: Binding(
                    get: { pour.pattern },
                    set: { value in
                        var next = pour
                        next.pattern = value
                        if value != .spiral { next.agitation = false }
                        onChange(next)
                    }
                )) {
                    ForEach(PourPattern.allCases) { pattern in
                        Text(pattern.label).tag(pattern)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}

private struct PushSuccessView: View {
    var action: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(BloomTheme.moss)
                Text(action == "updated" ? "Updated in xBloom" : "Created in xBloom")
                    .font(.system(.title, design: .serif).weight(.semibold))
                Text("Open the official xBloom app and look under My Recipes. Brew from there when the machine is ready.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BloomTheme.muted)
                if let url = URL(string: "xbloom://") {
                    Link("Open xBloom app", destination: url)
                        .buttonStyle(BloomButtonStyle())
                }
                Button("Done") { dismiss() }
                    .buttonStyle(BloomButtonStyle(filled: false))
            }
            .padding(28)
            .bloomBackground()
        }
        .presentationDetents([.medium])
    }
}
