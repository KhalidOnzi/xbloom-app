import Foundation
import Observation
import SwiftData
import UIKit

enum AppRoute: Hashable {
    case analyze
    case profile
    case recipe
}

@MainActor
@Observable
final class AppModel {
    var path: [AppRoute] = []
    var selectedTab = 0
    var showPushSuccess = false
    var frontImage: UIImage?
    var backImage: UIImage?
    var profile = CoffeeProfile()
    var recipe: BloomBrewRecipe?
    var isAnalyzing = false
    var isGenerating = false
    var isPushing = false
    var isSigningIn = false
    var errorMessage: String?
    var infoMessage: String?
    var lastPushAction: String?

    var geminiKey: String {
        didSet { KeychainStore.set(geminiKey, for: .geminiKey) }
    }

    var xbloomEmail: String {
        didSet { KeychainStore.set(xbloomEmail, for: .xbloomEmail) }
    }

    var xbloomPassword: String {
        didSet { KeychainStore.set(xbloomPassword, for: .xbloomPassword) }
    }

    var defaultDoseG: Double {
        didSet { Preferences.defaultDoseG = defaultDoseG }
    }

    var defaultRatio: Double {
        didSet { Preferences.defaultRatio = defaultRatio }
    }

    var hasGeminiKey: Bool {
        !geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasXBloomCredentials: Bool {
        !xbloomEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !xbloomPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var xbloomSession: XBloomCloudClient.Session? {
        guard
            let token = KeychainStore.string(for: .xbloomToken),
            let memberText = KeychainStore.string(for: .xbloomMemberId),
            let memberId = Int(memberText),
            !xbloomEmail.isEmpty
        else { return nil }
        return .init(email: xbloomEmail, memberId: memberId, token: token)
    }

    init() {
        geminiKey = KeychainStore.string(for: .geminiKey)
            ?? KeychainStore.string(for: .openAIKey)
            ?? ""
        xbloomEmail = KeychainStore.string(for: .xbloomEmail) ?? ""
        xbloomPassword = KeychainStore.string(for: .xbloomPassword) ?? ""
        defaultDoseG = Preferences.defaultDoseG
        defaultRatio = Preferences.defaultRatio
    }

    func resetSession() {
        path = []
        frontImage = nil
        backImage = nil
        profile = CoffeeProfile()
        recipe = nil
        isAnalyzing = false
        isGenerating = false
        isPushing = false
        errorMessage = nil
        infoMessage = nil
        lastPushAction = nil
        showPushSuccess = false
    }

    func analyzeBag() async {
        errorMessage = nil
        guard let frontImage else {
            errorMessage = "Photograph the front of the bag first."
            return
        }
        guard let frontJPEG = ImageProcessing.jpegData(from: frontImage) else {
            errorMessage = "Could not read that photo."
            return
        }
        let backJPEG = backImage.flatMap { ImageProcessing.jpegData(from: $0) }

        isAnalyzing = true
        path.append(.analyze)
        defer { isAnalyzing = false }

        do {
            if hasGeminiKey {
                profile = try await VisionClient.analyze(
                    frontJPEG: frontJPEG,
                    backJPEG: backJPEG,
                    apiKey: geminiKey
                )
            } else {
                errorMessage = "Add a Gemini key in Settings, or fill in the bag details by hand."
            }
            path.append(.profile)
        } catch {
            errorMessage = error.localizedDescription
            path.append(.profile)
        }
    }

    func generateRecipe(refineWithModel: Bool = true) async {
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }
        do {
            var next = RecipeEngine.baseline(
                profile: profile,
                doseG: defaultDoseG,
                ratio: defaultRatio
            )
            if refineWithModel, hasGeminiKey {
                do {
                    next = try await RecipeEngine.refine(
                        recipe: next,
                        profile: profile,
                        apiKey: geminiKey
                    )
                } catch {
                    next.rationale += " (Model refine skipped: \(error.localizedDescription))"
                }
            }
            try RecipeEngine.validate(next)
            recipe = next
            if !path.contains(.recipe) {
                path.append(.recipe)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyManualEdits(_ recipe: BloomBrewRecipe) {
        var next = recipe
        RecipeEngine.redistributeVolumes(recipe: &next)
        do {
            try RecipeEngine.validate(next)
            self.recipe = next
            errorMessage = nil
        } catch {
            self.recipe = next
            errorMessage = error.localizedDescription
        }
    }

    func signInToXBloom() async {
        errorMessage = nil
        infoMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let session = try await XBloomCloudClient.login(
                email: xbloomEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                password: xbloomPassword
            )
            persist(session)
            infoMessage = "Signed in to xBloom as \(session.email)."
        } catch {
            clearXBloomSession()
            errorMessage = error.localizedDescription
        }
    }

    func pushToXBloom(context: ModelContext, existing: SavedBrew? = nil) async {
        errorMessage = nil
        infoMessage = nil
        guard let recipe else {
            errorMessage = "Generate a recipe first."
            return
        }
        isPushing = true
        defer { isPushing = false }

        do {
            try RecipeEngine.validate(recipe)
            let session = try await ensureSession()
            let result = try await XBloomCloudClient.syncRecipe(session: session, recipe: recipe)
            lastPushAction = result.action
            showPushSuccess = true
            infoMessage = result.action == "updated"
                ? "Updated in your xBloom app."
                : "Created in your xBloom app."

            let record = try existing ?? SavedBrew.make(profile: profile, recipe: recipe)
            if existing != nil {
                try record.update(profile: profile, recipe: recipe)
            }
            record.xbloomTableId = result.tableId
            record.pushedAt = .now
            if existing == nil {
                context.insert(record)
            }
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveLocally(context: ModelContext) {
        guard let recipe else { return }
        do {
            context.insert(try SavedBrew.make(profile: profile, recipe: recipe))
            try context.save()
            infoMessage = "Saved on this iPhone."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func load(saved: SavedBrew) {
        if let profile = saved.profile {
            self.profile = profile
        }
        if let recipe = saved.recipe {
            self.recipe = recipe
        }
        path = [.profile, .recipe]
        selectedTab = 0
    }

    private func ensureSession() async throws -> XBloomCloudClient.Session {
        if let xbloomSession { return xbloomSession }
        guard hasXBloomCredentials else {
            throw XBloomCloudClient.CloudError.notSignedIn
        }
        let session = try await XBloomCloudClient.login(
            email: xbloomEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            password: xbloomPassword
        )
        persist(session)
        return session
    }

    private func persist(_ session: XBloomCloudClient.Session) {
        KeychainStore.set(session.token, for: .xbloomToken)
        KeychainStore.set(String(session.memberId), for: .xbloomMemberId)
    }

    func clearXBloomSession() {
        KeychainStore.delete(.xbloomToken)
        KeychainStore.delete(.xbloomMemberId)
    }
}
