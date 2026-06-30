import Foundation
import CryptoKit
import Combine

@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()
    
    @Published public var downloadProgress: [String: Double] = [:]
    
    private let updatesDir: URL
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.updatesDir = appSupport.appendingPathComponent("Orivo/updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)
    }
    
    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return machine == "arm64"
        #endif
    }
    
    public func getOnboardingRelease(for serviceId: String) -> (url: String, sha256: String, version: String)? {
        let isARM = UpdateManager.isAppleSilicon
        
        switch serviceId {
        case "torrserver":
            if isARM {
                return (
                    url: "https://github.com/YouROK/TorrServer/releases/download/MatriX.130/TorrServer-darwin-arm64",
                    sha256: "259e89bc02e54573fff1deea65d98f5fc05b159e7f36bb85c46202ffdcaebe5c",
                    version: "1.3.0"
                )
            } else {
                return (
                    url: "https://github.com/YouROK/TorrServer/releases/download/MatriX.130/TorrServer-darwin-amd64",
                    sha256: "e91a8176458be2be761e351e7007ce5ff3988b02daf7731b9ad4bda355d60343",
                    version: "1.3.0"
                )
            }
        case "jackett":
            if isARM {
                return (
                    url: "https://github.com/Jackett/Jackett/releases/latest/download/Jackett.Binaries.macOSARM64.tar.gz",
                    sha256: "skip",
                    version: "latest"
                )
            } else {
                return (
                    url: "https://github.com/Jackett/Jackett/releases/latest/download/Jackett.Binaries.macOS.tar.gz",
                    sha256: "skip",
                    version: "latest"
                )
            }
        default:
            return nil
        }
    }
    
    public func startInstallation(
        serviceId: String,
        urlString: String,
        sha256: String,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            LogManager.shared.log(serviceId: serviceId, text: "Invalid URL string: \(urlString)", isError: true)
            completion(false)
            return
        }
        
        ServiceManager.shared.setStatus(serviceId: serviceId, status: .installing)
        LogManager.shared.log(serviceId: serviceId, text: "Starting download from \(url.lastPathComponent)")
        
        let delegate = DownloadDelegate(serviceId: serviceId) { tempURL in
            DispatchQueue.main.async {
                if let tempURL = tempURL {
                    UpdateManager.shared.finalizeInstallation(
                        serviceId: serviceId,
                        tempURL: tempURL,
                        sha256: sha256,
                        completion: completion
                    )
                } else {
                    LogManager.shared.log(serviceId: serviceId, text: "Download failed.", isError: true)
                    ServiceManager.shared.setStatus(serviceId: serviceId, status: .failed)
                    completion(false)
                }
            }
        }
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        downloadTasks[serviceId] = task
        task.resume()
    }
    
    private func finalizeInstallation(
        serviceId: String,
        tempURL: URL,
        sha256: String,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        LogManager.shared.log(serviceId: serviceId, text: "Download completed. Verifying SHA256...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.verifySHA256(fileURL: tempURL, expectedHash: sha256) {
                LogManager.shared.log(serviceId: serviceId, text: "SHA256 checksum mismatch! Download is corrupted.", isError: true)
                DispatchQueue.main.async {
                    ServiceManager.shared.setStatus(serviceId: serviceId, status: .failed)
                    completion(false)
                }
                return
            }
            LogManager.shared.log(serviceId: serviceId, text: "SHA256 verification successful.")
            
            DispatchQueue.main.sync {
                if ServiceManager.shared.statuses[serviceId]?.isRunning ?? false {
                    LogManager.shared.log(serviceId: serviceId, text: "Stopping active service before replacing binary.")
                    ServiceManager.shared.stop(serviceId: serviceId)
                }
            }
            
            Thread.sleep(forTimeInterval: 1.0)
            
            DispatchQueue.main.sync {
                ServiceManager.shared.setStatus(serviceId: serviceId, status: .repairing)
            }
            
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let servicesDir = appSupport.appendingPathComponent("Orivo/services", isDirectory: true)
            let targetFolder = servicesDir.appendingPathComponent(serviceId, isDirectory: true)
            
            do {
                if FileManager.default.fileExists(atPath: targetFolder.path) {
                    try FileManager.default.removeItem(at: targetFolder)
                }
                
                try self.extract(archiveURL: tempURL, destinationURL: targetFolder, serviceId: serviceId)
                self.flattenDirectoryIfNecessary(at: targetFolder)
                
                let binaryName = serviceId == "torrserver" ? "TorrServer" : "jackett"
                let binaryPath = targetFolder.appendingPathComponent(binaryName).path
                
                if FileManager.default.fileExists(atPath: binaryPath) {
                    let chmod = Process()
                    chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                    chmod.arguments = ["+x", binaryPath]
                    try chmod.run()
                    chmod.waitUntilExit()
                }
                
                LogManager.shared.log(serviceId: serviceId, text: "Installation completed successfully.")
                
                DispatchQueue.main.async {
                    ServiceManager.shared.setStatus(serviceId: serviceId, status: .stopped)
                    completion(true)
                }
            } catch {
                LogManager.shared.log(serviceId: serviceId, text: "Extraction / setup failed: \(error.localizedDescription)", isError: true)
                DispatchQueue.main.async {
                    ServiceManager.shared.setStatus(serviceId: serviceId, status: .failed)
                    completion(false)
                }
            }
        }
    }
    
    nonisolated private func verifySHA256(fileURL: URL, expectedHash: String) -> Bool {
        if expectedHash.isEmpty || expectedHash.lowercased() == "skip" {
            return true
        }
        
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return hashString.lowercased() == expectedHash.lowercased()
    }
    
    nonisolated private func extract(archiveURL: URL, destinationURL: URL, serviceId: String) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        let pathExtension = archiveURL.pathExtension.lowercased()
        let process = Process()
        process.currentDirectoryURL = destinationURL
        
        if pathExtension == "zip" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", archiveURL.path, "-d", destinationURL.path]
            try process.run()
            process.waitUntilExit()
        } else if pathExtension == "gz" || pathExtension == "tgz" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", archiveURL.path, "-C", destinationURL.path]
            try process.run()
            process.waitUntilExit()
        } else {
            let binaryName = serviceId == "torrserver" ? "TorrServer" : "jackett"
            let destBinary = destinationURL.appendingPathComponent(binaryName)
            if FileManager.default.fileExists(atPath: destBinary.path) {
                try FileManager.default.removeItem(at: destBinary)
            }
            try FileManager.default.copyItem(at: archiveURL, to: destBinary)
            return
        }
        
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "ExtractorError",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Extraction process failed with code \(process.terminationStatus)"]
            )
        }
    }
    
    nonisolated private func flattenDirectoryIfNecessary(at dir: URL) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        
        if contents.count == 1, contents.first!.hasDirectoryPath {
            let subDir = contents.first!
            // Rename to avoid case-insensitive collisions (e.g. Jackett vs jackett on macOS)
            let tempSubDir = dir.appendingPathComponent("sub_temp_\(UUID().uuidString)")
            
            do {
                try fileManager.moveItem(at: subDir, to: tempSubDir)
                let subContents = try fileManager.contentsOfDirectory(at: tempSubDir, includingPropertiesForKeys: nil)
                for item in subContents {
                    let dest = dir.appendingPathComponent(item.lastPathComponent)
                    if fileManager.fileExists(atPath: dest.path) {
                        try? fileManager.removeItem(at: dest)
                    }
                    try fileManager.moveItem(at: item, to: dest)
                }
                try fileManager.removeItem(at: tempSubDir)
            } catch {
                LogManager.shared.log(serviceId: "system", text: "Flatten directory failed: \(error.localizedDescription)", isError: true)
            }
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let serviceId: String
    let completion: @Sendable (URL?) -> Void
    
    init(serviceId: String, completion: @escaping @Sendable (URL?) -> Void) {
        self.serviceId = serviceId
        self.completion = completion
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("Orivo/cache", isDirectory: true)
        
        let originalExtension = downloadTask.originalRequest?.url?.pathExtension ?? ""
        let filename = "\(serviceId)_downloaded_\(UUID().uuidString)"
        
        let destination: URL
        if !originalExtension.isEmpty {
            destination = cacheDir.appendingPathComponent(filename).appendingPathExtension(originalExtension)
        } else {
            let urlString = downloadTask.originalRequest?.url?.absoluteString ?? ""
            if urlString.contains(".tar.gz") {
                destination = cacheDir.appendingPathComponent(filename).appendingPathExtension("tar.gz")
            } else if urlString.contains(".gz") {
                destination = cacheDir.appendingPathComponent(filename).appendingPathExtension("gz")
            } else if urlString.contains(".zip") {
                destination = cacheDir.appendingPathComponent(filename).appendingPathExtension("zip")
            } else {
                destination = cacheDir.appendingPathComponent(filename)
            }
        }
        
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            completion(destination)
        } catch {
            completion(nil)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        EventBus.shared.post(.downloadProgress(serviceId: serviceId, progress: progress))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            LogManager.shared.log(serviceId: serviceId, text: "Download task error: \(error.localizedDescription)", isError: true)
            completion(nil)
        }
    }
}
