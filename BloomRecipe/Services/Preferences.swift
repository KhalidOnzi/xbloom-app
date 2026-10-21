import Foundation

enum Preferences {
    private static let doseKey = "defaultDoseG"
    private static let ratioKey = "defaultRatio"
    private static let serverKey = "serverURL"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverKey) ?? "http://127.0.0.1:8000" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: serverKey) }
    }

    static var defaultDoseG: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: doseKey) as? Double
            return stored ?? 15
        }
        set {
            UserDefaults.standard.set(min(18, max(5, newValue)), forKey: doseKey)
        }
    }

    static var defaultRatio: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: ratioKey) as? Double
            return stored ?? 16
        }
        set {
            UserDefaults.standard.set(min(18, max(13, newValue)), forKey: ratioKey)
        }
    }
}
