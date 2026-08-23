import Foundation

enum VisionClient {
    static func analyze(frontJPEG: Data, backJPEG: Data?, apiKey: String) async throws -> CoffeeProfile {
        var userContent: [[String: Any]] = [
            [
                "type": "text",
                "text": """
                Read this coffee bag label. Return JSON only with keys:
                name, roaster, origin, region, variety, process, roast, tastingNotes, roastDate, altitude, extraNotes.
                process must be one of: washed, natural, honey, anaerobic, other, unknown.
                roast must be one of: light, mediumLight, medium, mediumDark, dark, unknown.
                Use empty strings when a field is not visible. Do not invent a famous roaster if the bag is unreadable.
                """
            ],
            imagePayload(frontJPEG)
        ]
        if let backJPEG {
            userContent.append(imagePayload(backJPEG))
        }

        let raw = try await OpenAIClient.completeJSON(
            messages: [
                [
                    "role": "system",
                    "content": "You extract coffee-bag metadata for brew-recipe design. Be conservative. JSON only."
                ],
                [
                    "role": "user",
                    "content": userContent
                ]
            ],
            apiKey: apiKey
        )
        return try decodeProfile(from: raw)
    }

    private static func imagePayload(_ jpeg: Data) -> [String: Any] {
        [
            "type": "image_url",
            "image_url": [
                "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            ]
        ]
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
        throw OpenAIClient.ClientError.invalidResponse
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

enum OpenAIClient {
    enum ClientError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Add an OpenAI API key in Settings."
            case .invalidResponse:
                "The vision model returned something we could not read."
            case .http(let code, let body):
                "OpenAI request failed (\(code)): \(body)"
            }
        }
    }

    static func completeJSON(prompt: String, apiKey: String) async throws -> String {
        try await completeJSON(
            messages: [
                ["role": "user", "content": prompt]
            ],
            apiKey: apiKey
        )
    }

    static func completeJSON(messages: [[String: Any]], apiKey: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o",
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": messages
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(code, String(body.prefix(280)))
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw ClientError.invalidResponse
        }
        return text
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String?
            }
            var message: Message
        }
        var choices: [Choice]
    }
}
