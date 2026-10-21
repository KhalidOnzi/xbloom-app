import Foundation

enum VisionClient {
    static func analyze(frontJPEG: Data, backJPEG: Data?) async throws -> CoffeeProfile {
        try await BloomAPIClient.analyze(frontJPEG: frontJPEG, backJPEG: backJPEG)
    }
}
