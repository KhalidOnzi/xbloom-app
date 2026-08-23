import XCTest
@testable import BloomRecipe

final class RecipeEngineTests: XCTestCase {
    func testLightWashedUsesFourPoursAndHotterBloom() throws {
        let profile = CoffeeProfile(
            name: "Guji",
            origin: "Ethiopia",
            process: .washed,
            roast: .light,
            tastingNotes: "jasmine, bergamot"
        )
        let recipe = RecipeEngine.baseline(profile: profile, doseG: 15, ratio: 16)
        XCTAssertEqual(recipe.pours.count, 4)
        XCTAssertEqual(recipe.pours[0].name, "Bloom")
        XCTAssertGreaterThanOrEqual(recipe.pours[0].temperatureC, 92)
        XCTAssertGreaterThanOrEqual(recipe.pours[0].pauseSeconds, 38)
        XCTAssertTrue(recipe.grind >= 40 && recipe.grind <= 56)
        try RecipeEngine.validate(recipe)
        XCTAssertEqual(recipe.totalWaterMl.rounded(), (15 * 16).rounded())
    }

    func testDarkNaturalIsCoarserCoolerAndThreePours() throws {
        let profile = CoffeeProfile(
            name: "House Blend",
            process: .natural,
            roast: .dark
        )
        let recipe = RecipeEngine.baseline(profile: profile, doseG: 15, ratio: 16)
        XCTAssertEqual(recipe.pours.count, 3)
        XCTAssertLessThanOrEqual(recipe.pours[0].temperatureC, 90)
        XCTAssertGreaterThanOrEqual(recipe.grind, 62)
        try RecipeEngine.validate(recipe)
    }

    func testValidationRejectsIllegalGrind() {
        var recipe = RecipeEngine.baseline(profile: CoffeeProfile(name: "Test"), doseG: 15, ratio: 16)
        recipe.grind = 0
        XCTAssertThrowsError(try RecipeEngine.validate(recipe)) { error in
            XCTAssertEqual(error as? RecipeValidationError, .grindOutOfRange)
        }
    }

    func testValidationRejectsAgitationWithoutSpiral() {
        var recipe = RecipeEngine.baseline(profile: CoffeeProfile(name: "Test"), doseG: 15, ratio: 16)
        recipe.pours[0].pattern = .center
        recipe.pours[0].agitation = true
        XCTAssertThrowsError(try RecipeEngine.validate(recipe)) { error in
            XCTAssertEqual(error as? RecipeValidationError, .agitationRequiresSpiral(step: "Bloom"))
        }
    }

    func testValidationRejectsVolumeMismatch() {
        var recipe = RecipeEngine.baseline(profile: CoffeeProfile(name: "Test"), doseG: 15, ratio: 16)
        recipe.pours[0].volumeMl += 20
        XCTAssertThrowsError(try RecipeEngine.validate(recipe))
    }

    func testRedistributeRestoresDoseTimesRatio() throws {
        var recipe = RecipeEngine.baseline(profile: CoffeeProfile(name: "Test"), doseG: 18, ratio: 15)
        recipe.doseG = 12
        recipe.ratio = 16
        RecipeEngine.redistributeVolumes(recipe: &recipe)
        try RecipeEngine.validate(recipe)
        XCTAssertEqual(recipe.totalWaterMl.rounded(), 192)
    }

    func testRPMSnapsToLegalSteps() {
        XCTAssertEqual(RecipeEngine.snappedRPM(94), 90)
        XCTAssertEqual(RecipeEngine.snappedRPM(96), 100)
        XCTAssertEqual(RecipeEngine.snappedRPM(10), 60)
        XCTAssertEqual(RecipeEngine.snappedRPM(200), 120)
    }

    func testCloudRecipeUsesOmniDripperAndStudioModel() {
        let recipe = RecipeEngine.baseline(
            profile: CoffeeProfile(name: "Kenya AA", roast: .medium),
            doseG: 15,
            ratio: 16
        )
        let payload = XBloomCloudClient.cloudRecipe(from: recipe, name: recipe.xbloomAppName)
        XCTAssertEqual(payload["cupType"] as? Int, 2)
        XCTAssertEqual(payload["adaptedModel"] as? Int, 2)
        XCTAssertEqual(payload["theName"] as? String, "BloomRecipe · Kenya AA")
        XCTAssertEqual(payload["grandWater"] as? Double, 16)
        XCTAssertTrue((payload["pourDataJSONStr"] as? String)?.contains("Bloom") == true)
    }
}
