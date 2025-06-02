import Foundation
import CryptoKit

/// Status of a Whisper model
public enum ModelStatus {
    case available      // Available for download
    case downloading    // Currently downloading
    case installed      // Downloaded and verified
    case bundled        // Bundled with the app
    case failed         // Download/verification failed
}

/// Information about a Whisper model
public struct ModelInfo {
    public let name: String
    public let displayName: String
    public let description: String
    public let downloadSize: UInt64      // Size of download
    public let fileSize: UInt64          // Size when extracted/installed
    public let downloadURL: String
    public let checksum: String          // SHA256 checksum for verification
    public var status: ModelStatus
    public var downloadProgress: Double
    public var errorMessage: String?
    
    public init(
        name: String,
        displayName: String,
        description: String,
        downloadSize: UInt64,
        fileSize: UInt64,
        downloadURL: String,
        checksum: String,
        status: ModelStatus = .available,
        downloadProgress: Double = 0.0,
        errorMessage: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.downloadSize = downloadSize
        self.fileSize = fileSize
        self.downloadURL = downloadURL
        self.checksum = checksum
        self.status = status
        self.downloadProgress = downloadProgress
        self.errorMessage = errorMessage
    }
}

/// Result of a download operation
public struct DownloadResult {
    public let success: Bool
    public let filePath: String?
    public let error: String?
    public let bytesDownloaded: UInt64
    
    public init(success: Bool, filePath: String? = nil, error: String? = nil, bytesDownloaded: UInt64 = 0) {
        self.success = success
        self.filePath = filePath
        self.error = error
        self.bytesDownloaded = bytesDownloaded
    }
}

/// Manages Whisper model downloads, storage, and lifecycle
@MainActor
public class ModelManager: ObservableObject {
    public static let shared = ModelManager()
    
    // MARK: - Published Properties
    
    @Published public var availableModels: [ModelInfo] = []
    @Published public var activeModelName: String = "tiny.en" {
        didSet {
            UserDefaults.standard.set(activeModelName, forKey: "activeModelName")
        }
    }
    @Published public var totalStorageUsed: UInt64 = 0
    @Published public var availableDiskSpace: UInt64 = 0
    
    // MARK: - Private Properties
    
    private let modelsDirectory: URL
    private let urlSession: URLSession
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private let fileManager = FileManager.default
    
    // Base URLs for model downloads (Hugging Face)
    private let baseDownloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    
    // MARK: - Computed Properties
    
    public var installedModels: [ModelInfo] {
        return availableModels.filter { $0.status == .installed || $0.status == .bundled }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Set up models directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let whisperNodeDir = appSupport.appendingPathComponent("WhisperNode")
        self.modelsDirectory = whisperNodeDir.appendingPathComponent("Models")
        
        // Create models directory if it doesn't exist
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        // Configure URL session with progress tracking
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600 // 1 hour for large downloads
        self.urlSession = URLSession(configuration: config)
        
        // Load active model preference
        self.activeModelName = UserDefaults.standard.string(forKey: "activeModelName") ?? "tiny.en"
        
        // Initialize available models
        self.initializeModelList()
    }
    
    // MARK: - Public Methods
    
    /// Refresh the list of available models and their status
    public func refreshModels() async {
        await checkInstalledModels()
        await updateDiskSpace()
        calculateTotalStorageUsed()
    }
    
    /// Download a model with progress tracking and checksum verification
    public func downloadModel(_ model: ModelInfo) async {
        guard model.status != .downloading else { return }
        
        // Update model status
        updateModelStatus(model.name, status: .downloading, progress: 0.0)
        
        do {
            let result = await downloadWithProgress(model)
            
            if result.success, let filePath = result.filePath {
                // Verify checksum
                if await verifyChecksum(filePath: filePath, expectedChecksum: model.checksum) {
                    updateModelStatus(model.name, status: .installed, progress: 1.0)
                    await refreshModels()
                } else {
                    // Delete corrupted file
                    try? fileManager.removeItem(atPath: filePath)
                    updateModelStatus(model.name, status: .failed, progress: 0.0, error: "Checksum verification failed")
                }
            } else {
                updateModelStatus(model.name, status: .failed, progress: 0.0, error: result.error)
            }
        } catch {
            updateModelStatus(model.name, status: .failed, progress: 0.0, error: error.localizedDescription)
        }
    }
    
    /// Retry a failed download
    public func retryDownload(_ model: ModelInfo) async {
        guard model.status == .failed else { return }
        
        // Clean up any partial files
        let modelPath = modelsDirectory.appendingPathComponent("\(model.name).bin")
        try? fileManager.removeItem(at: modelPath)
        
        await downloadModel(model)
    }
    
    /// Delete an installed model
    public func deleteModel(_ model: ModelInfo) async {
        guard model.status == .installed else { return }
        
        let modelPath = modelsDirectory.appendingPathComponent("\(model.name).bin")
        
        do {
            try fileManager.removeItem(at: modelPath)
            updateModelStatus(model.name, status: .available, progress: 0.0)
            
            // If this was the active model, fallback to tiny.en
            if activeModelName == model.name {
                activeModelName = "tiny.en"
            }
            
            await refreshModels()
        } catch {
            print("Failed to delete model \(model.name): \(error.localizedDescription)")
        }
    }
    
    /// Get the file path for the active model
    public func getActiveModelPath() -> String? {
        guard let activeModel = availableModels.first(where: { $0.name == activeModelName }),
              activeModel.status == .installed || activeModel.status == .bundled else {
            return nil
        }
        
        if activeModel.status == .bundled {
            // Return bundled model path from app bundle
            return Bundle.main.path(forResource: activeModel.name, ofType: "bin")
        } else {
            // Return downloaded model path
            return modelsDirectory.appendingPathComponent("\(activeModel.name).bin").path
        }
    }
    
    /// Update available disk space
    public func updateDiskSpace() async {
        do {
            let resourceValues = try modelsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            availableDiskSpace = UInt64(resourceValues.volumeAvailableCapacity ?? 0)
        } catch {
            availableDiskSpace = 0
        }
    }
    
    // MARK: - Private Methods
    
    private func initializeModelList() {
        availableModels = [
            ModelInfo(
                name: "tiny.en",
                displayName: "Tiny English",
                description: "Fastest model, good for real-time use. English only.",
                downloadSize: 39 * 1024 * 1024,      // 39MB
                fileSize: 39 * 1024 * 1024,
                downloadURL: "\(baseDownloadURL)/ggml-tiny.en.bin",
                checksum: "d6a14c3a48a3e6739df9db90d03984b03cf9c41b6b7b29a8da8c7bbace5fefb4", // Placeholder
                status: .bundled  // Bundled with app
            ),
            ModelInfo(
                name: "small.en",
                displayName: "Small English",
                description: "Balanced speed and accuracy. English only.",
                downloadSize: 244 * 1024 * 1024,     // 244MB
                fileSize: 244 * 1024 * 1024,
                downloadURL: "\(baseDownloadURL)/ggml-small.en.bin",
                checksum: "d6a14c3a48a3e6739df9db90d03984b03cf9c41b6b7b29a8da8c7bbace5fefb5", // Placeholder
                status: .available
            ),
            ModelInfo(
                name: "medium.en",
                displayName: "Medium English",
                description: "Best accuracy, slower processing. English only.",
                downloadSize: 769 * 1024 * 1024,     // 769MB
                fileSize: 769 * 1024 * 1024,
                downloadURL: "\(baseDownloadURL)/ggml-medium.en.bin",
                checksum: "d6a14c3a48a3e6739df9db90d03984b03cf9c41b6b7b29a8da8c7bbace5fefb6", // Placeholder
                status: .available
            )
        ]
    }
    
    private func checkInstalledModels() async {
        for i in 0..<availableModels.count {
            let model = availableModels[i]
            
            if model.status == .bundled {
                continue // Skip bundled models
            }
            
            let modelPath = modelsDirectory.appendingPathComponent("\(model.name).bin")
            
            if fileManager.fileExists(atPath: modelPath.path) {
                // Check if file size matches expected
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: modelPath.path)
                    let fileSize = attributes[.size] as? UInt64 ?? 0
                    
                    if fileSize == model.fileSize {
                        availableModels[i].status = .installed
                    } else {
                        // File size mismatch, mark as available for re-download
                        try? fileManager.removeItem(at: modelPath)
                        availableModels[i].status = .available
                    }
                } catch {
                    availableModels[i].status = .available
                }
            } else {
                availableModels[i].status = .available
            }
        }
    }
    
    private func downloadWithProgress(_ model: ModelInfo) async -> DownloadResult {
        guard let url = URL(string: model.downloadURL) else {
            return DownloadResult(success: false, error: "Invalid download URL")
        }
        
        let destinationURL = modelsDirectory.appendingPathComponent("\(model.name).bin")
        
        // Remove any existing file
        try? fileManager.removeItem(at: destinationURL)
        
        do {
            let (tempURL, response) = try await urlSession.download(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                return DownloadResult(success: false, error: "HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            
            // Move temp file to final destination
            try fileManager.moveItem(at: tempURL, to: destinationURL)
            
            // Get actual file size
            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            let downloadedSize = attributes[.size] as? UInt64 ?? 0
            
            return DownloadResult(
                success: true,
                filePath: destinationURL.path,
                bytesDownloaded: downloadedSize
            )
            
        } catch {
            return DownloadResult(success: false, error: error.localizedDescription)
        }
    }
    
    private func verifyChecksum(filePath: String, expectedChecksum: String) async -> Bool {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let hash = SHA256.hash(data: data)
            let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
            return hashString.lowercased() == expectedChecksum.lowercased()
        } catch {
            print("Checksum verification error: \(error)")
            return false
        }
    }
    
    private func updateModelStatus(_ modelName: String, status: ModelStatus, progress: Double = 0.0, error: String? = nil) {
        if let index = availableModels.firstIndex(where: { $0.name == modelName }) {
            availableModels[index].status = status
            availableModels[index].downloadProgress = progress
            availableModels[index].errorMessage = error
        }
    }
    
    private func calculateTotalStorageUsed() {
        totalStorageUsed = 0
        
        for model in availableModels where model.status == .installed {
            let modelPath = modelsDirectory.appendingPathComponent("\(model.name).bin")
            
            do {
                let attributes = try fileManager.attributesOfItem(atPath: modelPath.path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                totalStorageUsed += fileSize
            } catch {
                // Ignore errors for this calculation
            }
        }
    }
}