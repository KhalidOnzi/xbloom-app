import Foundation

enum PourPattern: String, Codable, CaseIterable, Identifiable, Hashable {
    case spiral
    case ring
    case center

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spiral: "Spiral"
        case .ring: "Ring"
        case .center: "Center"
        }
    }

    /// Cloud pattern codes from the published xbloom-ble mapper.
    var cloudCode: Int {
        switch self {
        case .center: 1
        case .spiral, .ring: 2
        }
    }
}

struct PourStep: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var volumeMl: Double
    var temperatureC: Int
    var pattern: PourPattern
    var pauseSeconds: Int
    var rpm: Int
    var flowMlPerS: Double
    var agitation: Bool

    init(
        id: UUID = UUID(),
        name: String,
        volumeMl: Double,
        temperatureC: Int,
        pattern: PourPattern = .spiral,
        pauseSeconds: Int,
        rpm: Int,
        flowMlPerS: Double = 3.2,
        agitation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.volumeMl = volumeMl
        self.temperatureC = temperatureC
        self.pattern = pattern
        self.pauseSeconds = pauseSeconds
        self.rpm = rpm
        self.flowMlPerS = flowMlPerS
        self.agitation = agitation
    }
}

struct BloomBrewRecipe: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var doseG: Double
    var ratio: Double
    var grind: Int
    var rpm: Int
    var pours: [PourStep]
    var rationale: String

    init(
        id: UUID = UUID(),
        name: String,
        doseG: Double,
        ratio: Double,
        grind: Int,
        rpm: Int,
        pours: [PourStep],
        rationale: String
    ) {
        self.id = id
        self.name = name
        self.doseG = doseG
        self.ratio = ratio
        self.grind = grind
        self.rpm = rpm
        self.pours = pours
        self.rationale = rationale
    }

    var totalWaterMl: Double {
        pours.reduce(0) { $0 + $1.volumeMl }
    }

    var bloomPreview: String {
        "\(Int(doseG.rounded())) g · 1:\(ratio.formatted(.number.precision(.fractionLength(0...1)))) · grind \(grind)"
    }

    var xbloomAppName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled coffee" : trimmed
        if base.hasPrefix(Self.managedPrefix) { return base }
        return Self.managedPrefix + base
    }

    static let managedPrefix = "BloomRecipe · "
}

enum RecipeValidationError: LocalizedError, Equatable {
    case doseOutOfRange
    case grindOutOfRange
    case emptyPours
    case temperatureOutOfRange(step: String)
    case flowOutOfRange(step: String)
    case rpmOutOfRange(step: String)
    case pauseOutOfRange(step: String)
    case agitationRequiresSpiral(step: String)
    case volumeMismatch(expected: Double, actual: Double)

    var errorDescription: String? {
        switch self {
        case .doseOutOfRange:
            "Dose must be between 5 and 18 grams."
        case .grindOutOfRange:
            "Grind must be between 1 and 80."
        case .emptyPours:
            "A recipe needs at least one pour."
        case .temperatureOutOfRange(let step):
            "\(step) temperature must be between 40 and 95 °C."
        case .flowOutOfRange(let step):
            "\(step) flow must be between 3.0 and 3.5 ml/s."
        case .rpmOutOfRange(let step):
            "\(step) RPM must be 60–120 in steps of 10."
        case .pauseOutOfRange(let step):
            "\(step) pause must be between 0 and 255 seconds."
        case .agitationRequiresSpiral(let step):
            "\(step) can only agitate with a spiral pour."
        case .volumeMismatch(let expected, let actual):
            "Pour total (\(Self.format(actual)) ml) must equal dose × ratio (\(Self.format(expected)) ml)."
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
