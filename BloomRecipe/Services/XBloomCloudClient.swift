import Foundation
import Security

/// Unofficial xBloom account client, ported from the published MIT
/// `xbloom-ble` cloud module so a recipe you create here appears in
/// *your* official xBloom app. This talks only to your account and never
/// starts a brew.
enum XBloomCloudClient {
    static let baseURL = URL(string: "https://client-api.xbloom.com/")!
    static let managedPrefix = BloomBrewRecipe.managedPrefix

    struct Session: Equatable {
        var email: String
        var memberId: Int
        var token: String
    }

    struct RemoteRecipe: Identifiable, Equatable {
        var id: Int
        var name: String
    }

    enum CloudError: LocalizedError {
        case notSignedIn
        case loginFailed(String)
        case requestFailed(String)
        case encryptionFailed
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                "Sign in with your xBloom email and password in Settings."
            case .loginFailed(let info):
                "xBloom login failed: \(info)"
            case .requestFailed(let info):
                "xBloom request failed: \(info)"
            case .encryptionFailed:
                "Could not encrypt the xBloom request."
            case .invalidResponse:
                "xBloom returned an unexpected response."
            }
        }
    }

    static func login(email: String, password: String) async throws -> Session {
        let form: [String: Any] = [
            "interfaceVersion": 20_240_918,
            "skey": "testskey",
            "phoneType": "iOS",
            "clientType": 2,
            "languageType": 1,
            "email": email,
            "password": password,
            "jpushId": ""
        ]
        let response = try await postEncrypted(endpoint: "tMemberLogin.thtml", form: form)
        try check(response, what: "login")
        guard
            let member = response["member"] as? [String: Any],
            let memberId = intValue(member["tableId"]),
            let token = response["token"] as? String,
            !token.isEmpty
        else {
            throw CloudError.loginFailed(stringValue(response["info"]) ?? "missing token")
        }
        return Session(email: email, memberId: memberId, token: token)
    }

    static func listRecipes(session: Session) async throws -> [RemoteRecipe] {
        var form = authForm(session)
        form["pageNumber"] = 1
        form["countPerPage"] = 100
        form["adaptedModel"] = 0
        let response = try await postEncrypted(endpoint: "tuMyTeaRecipeCreated.tuhtml", form: form)
        try check(response, what: "list")
        let rows = response["list"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = intValue(row["tableId"]) else { return nil }
            return RemoteRecipe(id: id, name: stringValue(row["theName"]) ?? "")
        }
    }

    @discardableResult
    static func syncRecipe(session: Session, recipe: BloomBrewRecipe) async throws -> (tableId: Int?, action: String) {
        try RecipeEngine.validate(recipe)
        let named = recipe.xbloomAppName
        var payload = cloudRecipe(from: recipe, name: named)
        payload.merge(authForm(session)) { _, new in new }

        let existing = try await listRecipes(session: session).first { $0.name == named }
        if let existing {
            payload["tableId"] = existing.id
            let response = try await postEncrypted(endpoint: "tuRecipeUpdate.tuhtml", form: payload)
            try check(response, what: "update")
            return (existing.id, "updated")
        }

        let response = try await postEncrypted(endpoint: "tuRecipeAdd.tuhtml", form: payload)
        try check(response, what: "create")
        return (intValue(response["tableId"]), "added")
    }

    static func cloudRecipe(from recipe: BloomBrewRecipe, name: String) -> [String: Any] {
        let pours: [[String: Any]] = recipe.pours.enumerated().map { index, pour in
            [
                "theName": index == 0 ? "Bloom" : pour.name,
                "volume": pour.volumeMl,
                "temperature": Double(pour.temperatureC),
                "flowRate": pour.flowMlPerS,
                "pattern": pour.pattern.cloudCode,
                "pausing": pour.pauseSeconds,
                "isEnableVibrationBefore": 2,
                "isEnableVibrationAfter": pour.agitation ? 1 : 2
            ]
        }
        let pourJSON = compactJSONString(pours) ?? "[]"
        return [
            "theName": name,
            "dose": recipe.doseG,
            "grandWater": recipe.ratio,
            "grinderSize": Double(recipe.grind),
            "rpm": recipe.rpm,
            "cupType": 2,
            "adaptedModel": 2,
            "isEnableBypassWater": 2,
            "isSetGrinderSize": 1,
            "theColor": "#C9D5B8",
            "theSubsetId": 0,
            "bypassTemp": 85.0,
            "bypassVolume": 0.0,
            "subSetType": 2,
            "appPlace": [4],
            "createTimeStamp": Int(Date().timeIntervalSince1970 * 1000),
            "isShortcuts": 2,
            "pourDataJSONStr": pourJSON
        ]
    }

    private static func authForm(_ session: Session) -> [String: Any] {
        [
            "interfaceVersion": 20_240_918,
            "skey": "testskey",
            "phoneType": "iOS",
            "memberId": session.memberId,
            "clientType": 2,
            "languageType": 1,
            "token": session.token
        ]
    }

    private static func postEncrypted(endpoint: String, form: [String: Any]) async throws -> [String: Any] {
        let body = try RSAFormEncryption.encrypt(form)
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw CloudError.requestFailed("HTTP \(code) \(text.prefix(160))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudError.invalidResponse
        }
        return json
    }

    private static func check(_ response: [String: Any], what: String) throws {
        if stringValue(response["result"]) == "success" { return }
        let info = stringValue(response["info"]) ?? stringValue(response["error"]) ?? "\(response)"
        if what == "login" {
            throw CloudError.loginFailed(info)
        }
        throw CloudError.requestFailed(info)
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: number
        case let number as NSNumber: number.intValue
        case let text as String: Int(text)
        default: nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    private static func compactJSONString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum RSAFormEncryption {
    /// Public RSA key published by community xBloom clients (X.509 SPKI).
    private static let publicKeyB64 =
        "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC4LF40GZ72SdhMyl765K/i4nY5" +
        "CPcHz2Q1IKWKZ9S79xmK7G8pUhbVf4EZLvnNF1+9IvOFQUKV5Z7ZNNviqSpnql9" +
        "tAT+8+J/He0R7pcirvVSxgdr2i9V/C/gmqAEZ5qVTzRnd3uWdFoKzPdEBxP0Ipor" +
        "J1VBbCv90yBSOhVxO+QIDAQAB"

    private static let maxPlainBlock = 117

    static func encrypt(_ form: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(form),
              let json = try? JSONSerialization.data(withJSONObject: form, options: [])
        else {
            throw XBloomCloudClient.CloudError.encryptionFailed
        }
        let cipher = try encrypt(json)
        return cipher.base64EncodedString()
    }

    static func encrypt(_ plaintext: Data) throws -> Data {
        let key = try publicKey()
        var output = Data()
        var offset = 0
        if plaintext.isEmpty {
            return try encryptBlock(Data(), key: key)
        }
        while offset < plaintext.count {
            let end = min(offset + maxPlainBlock, plaintext.count)
            let block = plaintext.subdata(in: offset..<end)
            output.append(try encryptBlock(block, key: key))
            offset = end
        }
        return output
    }

    private static func encryptBlock(_ block: Data, key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            block as CFData,
            &error
        ) as Data? else {
            throw XBloomCloudClient.CloudError.encryptionFailed
        }
        return encrypted
    }

    private static func publicKey() throws -> SecKey {
        guard let der = Data(base64Encoded: publicKeyB64) else {
            throw XBloomCloudClient.CloudError.encryptionFailed
        }
        if let key = makeKey(from: der) {
            return key
        }
        // Some iOS versions prefer PKCS#1 over SPKI. Strip the typical 22-byte X.509 header.
        if der.count > 24, let key = makeKey(from: der.suffix(from: 22)) {
            return key
        }
        throw XBloomCloudClient.CloudError.encryptionFailed
    }

    private static func makeKey(from data: Data) -> SecKey? {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error)
    }
}
