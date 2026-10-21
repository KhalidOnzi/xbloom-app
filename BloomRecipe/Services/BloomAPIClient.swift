import Foundation

enum BloomAPIClient {
    enum APIError: LocalizedError {
        case missingServer
        case invalidURL
        case http(Int, String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingServer:
                "Add the FastAPI server URL in Settings (example: http://192.168.1.10:8000)."
            case .invalidURL:
                "The server URL is not valid."
            case .http(let code, let body):
                "Server error (\(code)): \(body)"
            case .invalidResponse:
                "The BloomRecipe server returned something we could not read."
            }
        }
    }

    static func rootURL() throws -> URL {
        let raw = Preferences.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw APIError.missingServer }
        guard let url = URL(string: raw) else { throw APIError.invalidURL }
        return url
    }

    static func analyze(frontJPEG: Data, backJPEG: Data?) async throws -> CoffeeProfile {
        var body: [String: Any] = ["frontJpegB64": frontJPEG.base64EncodedString()]
        if let backJPEG {
            body["backJpegB64"] = backJPEG.base64EncodedString()
        }
        let json = try await post(path: "analyze", body: body)
        let data = try JSONSerialization.data(withJSONObject: json)
        return try decodeProfile(from: data)
    }

    static func refine(profile: CoffeeProfile, recipe: BloomBrewRecipe) async throws -> String {
        let encoder = JSONEncoder()
        let profileObj = try JSONSerialization.jsonObject(with: encoder.encode(profile))
        let recipeObj = try JSONSerialization.jsonObject(with: encoder.encode(recipe))
        let json = try await post(path: "refine", body: [
            "profile": profileObj,
            "recipe": recipeObj
        ])
        let data = try JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func login(email: String, password: String) async throws -> XBloomCloudClient.Session {
        let json = try await post(path: "xbloom/login", body: [
            "email": email,
            "password": password
        ])
        guard let token = json["token"] as? String, !token.isEmpty else {
            throw APIError.invalidResponse
        }
        let memberId: Int
        if let value = json["memberId"] as? Int {
            memberId = value
        } else if let value = json["memberId"] as? NSNumber {
            memberId = value.intValue
        } else {
            throw APIError.invalidResponse
        }
        return .init(email: email, memberId: memberId, token: token)
    }

    static func syncRecipe(
        email: String,
        password: String,
        recipe: BloomBrewRecipe
    ) async throws -> (tableId: Int?, action: String) {
        let encoder = JSONEncoder()
        let recipeObj = try JSONSerialization.jsonObject(with: encoder.encode(recipe))
        let json = try await post(path: "xbloom/sync", body: [
            "email": email,
            "password": password,
            "recipe": recipeObj
        ])
        let action = (json["action"] as? String) ?? "added"
        let tableId = json["tableId"] as? Int ?? (json["tableId"] as? NSNumber)?.intValue
        return (tableId, action)
    }

    private static func post(path: String, body: [String: Any]) async throws -> [String: Any] {
        let root = try rootURL().absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/\(path)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(code) {
            let text = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw APIError.http(code, String(text.prefix(280)))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return json
    }

    private static func decodeProfile(from data: Data) throws -> CoffeeProfile {
        if let dto = try? JSONDecoder().decode(APIProfile.self, from: data) {
            return dto.profile
        }
        throw APIError.invalidResponse
    }
}

private struct APIProfile: Decodable {
    var name: String?
    var roaster: String?
    var origin: String?
    var region: String?
    var variety: String?
    var process: String?
    var roast: String?
    var tastingNotes: String?
    var roastDate: String?
    var altitude: String?
    var extraNotes: String?

    var profile: CoffeeProfile {
        CoffeeProfile(
            name: name ?? "",
            roaster: roaster ?? "",
            origin: origin ?? "",
            region: region ?? "",
            variety: variety ?? "",
            process: ProcessMethod(rawValue: process ?? "") ?? .unknown,
            roast: RoastLevel(rawValue: roast ?? "") ?? .unknown,
            tastingNotes: tastingNotes ?? "",
            roastDate: roastDate ?? "",
            altitude: altitude ?? "",
            extraNotes: extraNotes ?? ""
        )
    }
}
