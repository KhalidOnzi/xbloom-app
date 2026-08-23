import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))

                VStack(alignment: .leading, spacing: 12) {
                    Text("GEMINI")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BloomTheme.muted)
                    SecureField("API key", text: $model.geminiKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                    Text("Used on this iPhone to read bag photos and refine recipes. Get a key at aistudio.google.com. It stays in the Keychain.")
                        .font(.footnote)
                        .foregroundStyle(BloomTheme.muted)
                }
                .bloomCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("XBLOOM ACCOUNT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BloomTheme.muted)
                    TextField("Email", text: $model.xbloomEmail)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $model.xbloomPassword)
                        .textContentType(.password)
                    Button {
                        Task { await model.signInToXBloom() }
                    } label: {
                        if model.isSigningIn {
                            ProgressView().tint(.white)
                        } else {
                            Text(model.xbloomSession == nil ? "Sign in" : "Refresh session")
                        }
                    }
                    .buttonStyle(BloomButtonStyle())
                    .disabled(!model.hasXBloomCredentials || model.isSigningIn)

                    if model.xbloomSession != nil {
                        Text("Signed in. Recipes will appear in the official xBloom app under My Recipes.")
                            .font(.footnote)
                            .foregroundStyle(BloomTheme.moss)
                    }
                }
                .bloomCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("DEFAULT CUP")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BloomTheme.muted)
                    Stepper(
                        "Dose  \(model.defaultDoseG.formatted(.number.precision(.fractionLength(1)))) g",
                        value: $model.defaultDoseG,
                        in: 5...18,
                        step: 0.5
                    )
                    Stepper(
                        "Ratio  1:\(model.defaultRatio.formatted(.number.precision(.fractionLength(1))))",
                        value: $model.defaultRatio,
                        in: 13...18,
                        step: 0.5
                    )
                }
                .bloomCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("UNOFFICIAL CONNECTION")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BloomTheme.muted)
                    Text("xBloom does not offer a public recipe API. BloomRecipe signs into your own account using the community-published cloud protocol so a recipe can appear in the official app. That connection can break if xBloom changes their servers. BloomRecipe never starts a brew and never talks to the machine over Bluetooth.")
                        .font(.footnote)
                        .foregroundStyle(BloomTheme.muted)
                }
                .bloomCard()

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(BloomTheme.clay)
                }
                if let infoMessage = model.infoMessage {
                    Text(infoMessage)
                        .font(.footnote)
                        .foregroundStyle(BloomTheme.moss)
                }
            }
            .padding(20)
        }
        .bloomBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
