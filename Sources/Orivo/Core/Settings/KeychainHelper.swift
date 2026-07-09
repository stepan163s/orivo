import Foundation

public final class KeychainHelper: @unchecked Sendable {
    public static let shared = KeychainHelper()
    
    private let fileURL: URL
    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private let salt: [UInt8] = [83, 101, 99, 114, 101, 116, 83, 97, 108, 116, 75, 101, 121, 57, 57] // "SecretSaltKey99"
    
    private init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0]
        self.fileURL = appSupport.appendingPathComponent("Orivo/config/.secrets.dat")
        loadFromFile()
    }
    
    private func loadFromFile() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                var decrypted: [String: String] = [:]
                for (k, v) in json {
                    if let decodedData = Data(base64Encoded: v) {
                        decrypted[k] = decrypt(decodedData)
                    }
                }
                self.cache = decrypted
            }
        } catch {
            // Fallback silently
        }
    }
    
    private func saveToFile() {
        do {
            var encrypted: [String: String] = [:]
            for (k, v) in cache {
                encrypted[k] = encrypt(v).base64EncodedString()
            }
            let data = try JSONSerialization.data(withJSONObject: encrypted, options: [])
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Fallback silently
        }
    }
    
    private func encrypt(_ value: String) -> Data {
        let bytes = Array(value.utf8)
        var result = [UInt8]()
        for i in 0..<bytes.count {
            result.append(bytes[i] ^ salt[i % salt.count])
        }
        return Data(result)
    }
    
    private func decrypt(_ data: Data) -> String {
        let bytes = Array(data)
        var result = [UInt8]()
        for i in 0..<bytes.count {
            result.append(bytes[i] ^ salt[i % salt.count])
        }
        return String(bytes: result, encoding: .utf8) ?? ""
    }
    
    public func save(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = value
        saveToFile()
    }
    
    public func load(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let val = cache[key]
        return (val == nil || val!.isEmpty) ? nil : val
    }
    
    public func delete(key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: key)
        saveToFile()
    }
}
