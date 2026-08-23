import Foundation

enum RecipeEngine {
    static func baseline(
        profile: CoffeeProfile,
        doseG: Double = Preferences.defaultDoseG,
        ratio: Double = Preferences.defaultRatio
    ) -> BloomBrewRecipe {
        let dose = clamp(doseG, min: 5, max: 18)
        let brewRatio = clamp(adjustedRatio(profile: profile, requested: ratio), min: 13, max: 18)
        let grind = grindSetting(for: profile)
        let rpm = rpmSetting(for: profile)
        let pours = pourPlan(profile: profile, dose: dose, ratio: brewRatio, rpm: rpm)
        return BloomBrewRecipe(
            name: profile.displayName,
            doseG: dose,
            ratio: brewRatio,
            grind: grind,
            rpm: rpm,
            pours: pours,
            rationale: baselineRationale(profile: profile, grind: grind, rpm: rpm, dose: dose, ratio: brewRatio)
        )
    }

    static func refine(
        recipe: BloomBrewRecipe,
        profile: CoffeeProfile,
        apiKey: String
    ) async throws -> BloomBrewRecipe {
        let prompt = refinePrompt(profile: profile, recipe: recipe)
        let raw = try await GeminiClient.completeJSON(prompt: prompt, apiKey: apiKey)
        let patch = try decodeRefinePatch(from: raw)
        var next = recipe
        if let grind = patch.grind { next.grind = grind }
        if let rpm = patch.rpm { next.rpm = snappedRPM(rpm) }
        if let rationale = patch.rationale, !rationale.isEmpty { next.rationale = rationale }
        if let pours = patch.pours, !pours.isEmpty {
            next.pours = pours.enumerated().map { index, pour in
                existingOrNewPour(pour, fallback: next.pours[safe: index], index: index, defaultRPM: next.rpm)
            }
        }
        try validate(next)
        return next
    }

    static func validate(_ recipe: BloomBrewRecipe) throws {
        if recipe.doseG < 5 || recipe.doseG > 18 {
            throw RecipeValidationError.doseOutOfRange
        }
        if recipe.grind < 1 || recipe.grind > 80 {
            throw RecipeValidationError.grindOutOfRange
        }
        if recipe.pours.isEmpty {
            throw RecipeValidationError.emptyPours
        }

        for pour in recipe.pours {
            if pour.temperatureC < 40 || pour.temperatureC > 95 {
                throw RecipeValidationError.temperatureOutOfRange(step: pour.name)
            }
            if pour.flowMlPerS < 3.0 || pour.flowMlPerS > 3.5 {
                throw RecipeValidationError.flowOutOfRange(step: pour.name)
            }
            if pour.pauseSeconds < 0 || pour.pauseSeconds > 255 {
                throw RecipeValidationError.pauseOutOfRange(step: pour.name)
            }
            if pour.rpm < 60 || pour.rpm > 120 || pour.rpm % 10 != 0 {
                throw RecipeValidationError.rpmOutOfRange(step: pour.name)
            }
            if pour.agitation && pour.pattern != .spiral {
                throw RecipeValidationError.agitationRequiresSpiral(step: pour.name)
            }
        }

        let expected = (recipe.doseG * recipe.ratio).rounded()
        let actual = recipe.pours.reduce(0) { $0 + $1.volumeMl }.rounded()
        if abs(expected - actual) > 1 {
            throw RecipeValidationError.volumeMismatch(expected: expected, actual: actual)
        }
    }

    static func redistributeVolumes(recipe: inout BloomBrewRecipe) {
        let target = (recipe.doseG * recipe.ratio).rounded()
        guard !recipe.pours.isEmpty else { return }
        let current = recipe.pours.reduce(0) { $0 + $1.volumeMl }
        guard current > 0 else { return }
        var remaining = target
        for index in recipe.pours.indices {
            if index == recipe.pours.indices.last {
                recipe.pours[index].volumeMl = remaining
            } else {
                let share = (recipe.pours[index].volumeMl / current * target).rounded()
                recipe.pours[index].volumeMl = max(27, share)
                remaining -= recipe.pours[index].volumeMl
            }
        }
        if remaining != recipe.pours[recipe.pours.count - 1].volumeMl {
            recipe.pours[recipe.pours.count - 1].volumeMl = max(27, remaining)
        }
    }

    // MARK: - Rules

    static func grindSetting(for profile: CoffeeProfile) -> Int {
        var grind = 58
        switch profile.roast {
        case .light: grind -= 6
        case .mediumLight: grind -= 3
        case .medium, .unknown: break
        case .mediumDark: grind += 4
        case .dark: grind += 8
        }
        switch profile.process {
        case .washed, .honey: grind -= 2
        case .natural: grind += 3
        case .anaerobic: grind += 2
        case .other, .unknown: break
        }
        if looksDense(profile) { grind -= 2 }
        return clamp(grind, min: 40, max: 72)
    }

    static func rpmSetting(for profile: CoffeeProfile) -> Int {
        let rpm: Int
        switch profile.roast {
        case .light, .mediumLight: rpm = 90
        case .medium, .unknown: rpm = 100
        case .mediumDark, .dark: rpm = 110
        }
        return snappedRPM(rpm)
    }

    static func pourPlan(profile: CoffeeProfile, dose: Double, ratio: Double, rpm: Int) -> [PourStep] {
        let total = (dose * ratio).rounded()
        let bloomML = clamp((dose * bloomMultiplier(for: profile)).rounded(), min: 30, max: 50)
        let rest = max(total - bloomML, 54)
        let bloomTemp = temperature(for: profile, offset: 1)
        let mainTemp = temperature(for: profile, offset: 0)
        let finishTemp = temperature(for: profile, offset: -1)
        let bloomPause = bloomPauseSeconds(for: profile)
        let flow = flowRate(for: profile)
        let useFourPours = profile.roast == .light && (profile.process == .washed || profile.process == .honey)

        var pours: [PourStep] = [
            PourStep(
                name: "Bloom",
                volumeMl: bloomML,
                temperatureC: bloomTemp,
                pattern: .spiral,
                pauseSeconds: bloomPause,
                rpm: rpm,
                flowMlPerS: 3.0,
                agitation: profile.roast == .light || profile.roast == .mediumLight
            )
        ]

        if useFourPours {
            let second = (rest * 0.28).rounded()
            let third = (rest * 0.36).rounded()
            let fourth = rest - second - third
            pours.append(PourStep(name: "Pour 2", volumeMl: second, temperatureC: bloomTemp, pauseSeconds: 12, rpm: rpm, flowMlPerS: flow))
            pours.append(PourStep(name: "Pour 3", volumeMl: third, temperatureC: mainTemp, pauseSeconds: 10, rpm: rpm, flowMlPerS: flow))
            pours.append(PourStep(name: "Pour 4", volumeMl: fourth, temperatureC: finishTemp, pauseSeconds: 5, rpm: rpm, flowMlPerS: min(3.5, flow + 0.1)))
        } else {
            let second = (rest * 0.52).rounded()
            let third = rest - second
            pours.append(PourStep(name: "Pour 2", volumeMl: second, temperatureC: mainTemp, pauseSeconds: 10, rpm: rpm, flowMlPerS: flow))
            pours.append(PourStep(name: "Pour 3", volumeMl: third, temperatureC: finishTemp, pauseSeconds: 5, rpm: rpm, flowMlPerS: flow))
        }
        return pours
    }

    private static func temperature(for profile: CoffeeProfile, offset: Int) -> Int {
        let base: Int
        switch profile.roast {
        case .light: base = 93
        case .mediumLight: base = 93
        case .medium, .unknown: base = 92
        case .mediumDark: base = 90
        case .dark: base = 88
        }
        var value = base + offset
        if profile.process == .natural || profile.process == .anaerobic {
            value -= 1
        }
        return clamp(value, min: 86, max: 95)
    }

    private static func bloomMultiplier(for profile: CoffeeProfile) -> Double {
        switch profile.roast {
        case .light, .mediumLight: 3.0
        case .dark, .mediumDark: 2.4
        case .medium, .unknown: 2.8
        }
    }

    private static func bloomPauseSeconds(for profile: CoffeeProfile) -> Int {
        switch profile.roast {
        case .light: 42
        case .mediumLight: 38
        case .medium, .unknown: 35
        case .mediumDark: 30
        case .dark: 26
        }
    }

    private static func flowRate(for profile: CoffeeProfile) -> Double {
        switch profile.roast {
        case .light, .mediumLight: 3.2
        case .dark: 3.4
        default: 3.3
        }
    }

    private static func adjustedRatio(profile: CoffeeProfile, requested: Double) -> Double {
        var ratio = requested
        if profile.roast == .dark { ratio -= 0.5 }
        if profile.process == .natural { ratio -= 0.5 }
        return ratio
    }

    private static func looksDense(_ profile: CoffeeProfile) -> Bool {
        let haystack = "\(profile.origin) \(profile.region) \(profile.altitude) \(profile.variety)".lowercased()
        return haystack.contains("ethiopia")
            || haystack.contains("kenya")
            || haystack.contains("gesha")
            || haystack.contains("geisha")
            || profile.altitude.contains(where: \.isNumber)
    }

    private static func baselineRationale(
        profile: CoffeeProfile,
        grind: Int,
        rpm: Int,
        dose: Double,
        ratio: Double
    ) -> String {
        let roast = profile.roast == .unknown ? "unspecified roast" : profile.roast.label.lowercased()
        let process = profile.process == .unknown ? "unknown process" : profile.process.label.lowercased()
        var text = "Built for \(profile.displayName) as a \(roast) \(process) coffee. "
        text += "Dose is \(Int(dose.rounded())) g at 1:\(ratio.formatted(.number.precision(.fractionLength(0...1)))) on grind \(grind) / \(rpm) RPM. "
        switch profile.roast {
        case .light, .mediumLight:
            text += "A hotter, longer bloom helps a denser light roast degas before the main pours."
        case .dark, .mediumDark:
            text += "A slightly coarser grind and cooler water keep a darker roast from turning bitter."
        default:
            text += "A three-pour Rao-style structure is a reliable daily cup on the Omni dripper."
        }
        if !profile.tastingNotes.isEmpty {
            text += " Aimed at the bag notes: \(profile.tastingNotes)."
        }
        return text
    }

    private static func refinePrompt(profile: CoffeeProfile, recipe: BloomBrewRecipe) -> String {
        """
        You refine xBloom Studio Omni Dripper recipes. Stay inside these hard limits:
        dose 5-18 g, grind 1-80, pour temp 40-95 C, flow 3.0-3.5 ml/s, rpm 60-120 in steps of 10,
        pause 0-255 s, patterns spiral|ring|center, agitation only with spiral.
        Pour volumes MUST sum to dose * ratio (rounded to whole ml).

        Return JSON only:
        {
          "grind": <int>,
          "rpm": <int>,
          "rationale": "<2-4 sentences>",
          "pours": [
            {
              "name": "Bloom",
              "volumeMl": <number>,
              "temperatureC": <int>,
              "pattern": "spiral",
              "pauseSeconds": <int>,
              "rpm": <int>,
              "flowMlPerS": <number>,
              "agitation": <bool>
            }
          ]
        }

        Coffee profile:
        \(jsonString(profile))

        Baseline recipe (already valid — make small, justified changes only):
        \(jsonString(recipe))
        """
    }

    private static func decodeRefinePatch(from raw: String) throws -> RefinePatch {
        let data = Data(raw.utf8)
        do {
            return try JSONDecoder().decode(RefinePatch.self, from: data)
        } catch {
            if let extracted = extractJSONObject(from: raw) {
                return try JSONDecoder().decode(RefinePatch.self, from: Data(extracted.utf8))
            }
            throw error
        }
    }

    private static func existingOrNewPour(_ patch: RefinePour, fallback: PourStep?, index: Int, defaultRPM: Int) -> PourStep {
        PourStep(
            id: fallback?.id ?? UUID(),
            name: patch.name ?? fallback?.name ?? (index == 0 ? "Bloom" : "Pour \(index + 1)"),
            volumeMl: patch.volumeMl ?? fallback?.volumeMl ?? 40,
            temperatureC: patch.temperatureC ?? fallback?.temperatureC ?? 92,
            pattern: patch.pattern ?? fallback?.pattern ?? .spiral,
            pauseSeconds: patch.pauseSeconds ?? fallback?.pauseSeconds ?? 10,
            rpm: snappedRPM(patch.rpm ?? fallback?.rpm ?? defaultRPM),
            flowMlPerS: patch.flowMlPerS ?? fallback?.flowMlPerS ?? 3.2,
            agitation: patch.agitation ?? fallback?.agitation ?? false
        )
    }

    private static func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else { return nil }
        return String(raw[start...end])
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    static func snappedRPM(_ value: Int) -> Int {
        let snapped = Int((Double(value) / 10.0).rounded() * 10)
        return clamp(snapped, min: 60, max: 120)
    }

    static func clamp<T: Comparable>(_ value: T, min lower: T, max upper: T) -> T {
        Swift.min(upper, Swift.max(lower, value))
    }
}

private struct RefinePatch: Decodable {
    var grind: Int?
    var rpm: Int?
    var rationale: String?
    var pours: [RefinePour]?
}

private struct RefinePour: Decodable {
    var name: String?
    var volumeMl: Double?
    var temperatureC: Int?
    var pattern: PourPattern?
    var pauseSeconds: Int?
    var rpm: Int?
    var flowMlPerS: Double?
    var agitation: Bool?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
