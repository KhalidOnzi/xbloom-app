import Foundation
import SwiftData

@Model
final class SavedBrew {
    var id: UUID
    var createdAt: Date
    var coffeeName: String
    var roaster: String
    var origin: String
    var profileJSON: Data
    var recipeJSON: Data
    var xbloomTableId: Int?
    var pushedAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        coffeeName: String,
        roaster: String,
        origin: String,
        profileJSON: Data,
        recipeJSON: Data,
        xbloomTableId: Int? = nil,
        pushedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.coffeeName = coffeeName
        self.roaster = roaster
        self.origin = origin
        self.profileJSON = profileJSON
        self.recipeJSON = recipeJSON
        self.xbloomTableId = xbloomTableId
        self.pushedAt = pushedAt
    }

    var profile: CoffeeProfile? {
        try? JSONDecoder().decode(CoffeeProfile.self, from: profileJSON)
    }

    var recipe: BloomBrewRecipe? {
        try? JSONDecoder().decode(BloomBrewRecipe.self, from: recipeJSON)
    }

    var subtitle: String {
        [roaster, origin]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    static func make(profile: CoffeeProfile, recipe: BloomBrewRecipe) throws -> SavedBrew {
        let encoder = JSONEncoder()
        return SavedBrew(
            coffeeName: recipe.name,
            roaster: profile.roaster,
            origin: profile.origin,
            profileJSON: try encoder.encode(profile),
            recipeJSON: try encoder.encode(recipe)
        )
    }

    func update(profile: CoffeeProfile, recipe: BloomBrewRecipe) throws {
        let encoder = JSONEncoder()
        coffeeName = recipe.name
        roaster = profile.roaster
        origin = profile.origin
        profileJSON = try encoder.encode(profile)
        recipeJSON = try encoder.encode(recipe)
    }
}
