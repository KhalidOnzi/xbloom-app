import Foundation

enum VisionClient {
    static func analyze(frontJPEG: Data, backJPEG: Data?, apiKey: String) async throws -> CoffeeProfile {
        var images = [frontJPEG]
        if let backJPEG {
            images.append(backJPEG)
        }

        let raw = try await GeminiClient.completeJSON(
            prompt: """
            Read this coffee bag label. Return JSON only with keys:
            name, roaster, origin, region, variety, process, roast, tastingNotes, roastDate, altitude, extraNotes.
            process must be one of: washed, natural, honey, anaerobic, other, unknown.
            roast must be one of: light, mediumLight, medium, mediumDark, dark, unknown.
            Use empty strings when a field is not visible. Do not invent a famous roaster if the bag is unreadable.
            """,
            system: "You extract coffee-bag metadata for brew-recipe design. Be conservative. JSON only.",
            images: images,
            apiKey: apiKey
        )
        return try decodeProfile(from: raw)
    }

    private static func decodeProfile(from raw: String) throws -> CoffeeProfile {
        let data = Data(raw.utf8)
        let decoder = JSONDecoder()
        if let dto = try? decoder.decode(ProfileDTO.self, from: data) {
            return dto.profile
        }
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            let slice = String(raw[start...end])
            let dto = try decoder.decode(ProfileDTO.self, from: Data(slice.utf8))
            return dto.profile
        }
        throw GeminiClient.ClientError.invalidResponse
    }
}

private struct ProfileDTO: Decodable {
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

enum GeminiClient {
    static let model = "gemini-2.0-flash"

    enum ClientError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Add a Gemini API key in Settings."
            case .invalidResponse:
                "Gemini returned something we could not read."
            case .http(let code, let body):
                "Gemini request failed (\(code)): \(body)"
            }
        }
    }

    static func completeJSON(prompt: String, apiKey: String) async throws -> String {
        try await completeJSON(prompt: prompt, system: nil, images: [], apiKey: apiKey)
    }

    static func completeJSON(
        prompt: String,
        system: String?,
        images: [Data],
        apiKey: String
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.missingAPIKey
        }

        var parts: [[String: Any]] = [["text": prompt]]
        for image in images {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": image.base64EncodedString()
                ]
            ])
        }

        var body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": parts
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]
        if let system, !system.isEmpty {
            body["systemInstruction"] = [
                "parts": [["text": system]]
            ]
        }

        var request = URLRequest(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        )
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(code, String(text.prefix(280)))
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text, !text.isEmpty else {
            throw ClientError.invalidResponse
        }
        return text
    }

    private struct GenerateResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    var text: String?
                }
                var parts: [Part]
            }
            var content: Content
        }
        var candidates: [Candidate]
    }
}
