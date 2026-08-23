import Foundation

enum RoastLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .mediumLight: "Medium-light"
        case .medium: "Medium"
        case .mediumDark: "Medium-dark"
        case .dark: "Dark"
        case .unknown: "Unknown"
        }
    }
}

enum ProcessMethod: String, Codable, CaseIterable, Identifiable, Hashable {
    case washed
    case natural
    case honey
    case anaerobic
    case other
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .washed: "Washed"
        case .natural: "Natural"
        case .honey: "Honey"
        case .anaerobic: "Anaerobic"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }
}

struct CoffeeProfile: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var roaster: String
    var origin: String
    var region: String
    var variety: String
    var process: ProcessMethod
    var roast: RoastLevel
    var tastingNotes: String
    var roastDate: String
    var altitude: String
    var extraNotes: String

    init(
        id: UUID = UUID(),
        name: String = "",
        roaster: String = "",
        origin: String = "",
        region: String = "",
        variety: String = "",
        process: ProcessMethod = .unknown,
        roast: RoastLevel = .unknown,
        tastingNotes: String = "",
        roastDate: String = "",
        altitude: String = "",
        extraNotes: String = ""
    ) {
        self.id = id
        self.name = name
        self.roaster = roaster
        self.origin = origin
        self.region = region
        self.variety = variety
        self.process = process
        self.roast = roast
        self.tastingNotes = tastingNotes
        self.roastDate = roastDate
        self.altitude = altitude
        self.extraNotes = extraNotes
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let originName = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        if !originName.isEmpty { return originName }
        return "Untitled coffee"
    }

    var subtitle: String {
        [roaster, origin, process == .unknown ? "" : process.label]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var isSparse: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && tastingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
