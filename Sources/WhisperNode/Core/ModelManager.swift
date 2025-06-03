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

/// Metadata for tracking model installations
private struct ModelMetadata: Codable {
    let name: String
    let version: String
    let downloadedDate: Date
    let fileSize: UInt64
    let checksum: String
    let downloadURL: String
    
    init(name: String, version: String = "1.0", downloadedDate: Date = Date(), fileSize: UInt64, checksum: String, downloadURL: String) {
        self.name = name
        self.version = version
        self.downloadedDate = downloadedDate
        self.fileSize = fileSize
        self.checksum = checksum
        self.downloadURL = downloadURL
    }
}

/// Container for all model metadata
private struct ModelsMetadata: Codable {
    var models: [String: ModelMetadata] = [:]
    
    mutating func addModel(_ metadata: ModelMetadata) {
        models[metadata.name] = metadata
    }
    
    mutating func removeModel(_ name: String) {
        models.removeValue(forKey: name)
    }
    
    func getModel(_ name: String) -> ModelMetadata? {
        return models[name]
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
    
    // MARK: - Constants
    
    private static let requestTimeout: TimeInterval = 30 // 30 seconds for request timeout
    private static let resourceTimeout: TimeInterval = 3600 // 1 hour for large downloads
    private static let modelFileExtension = ".bin"
    
    // MARK: - Private Properties
    
    private let modelsDirectory: URL
    private let tempDirectory: URL
    private let metadataURL: URL
    private let urlSession: URLSession
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private let fileManager = FileManager.default
    private let errorManager = ErrorHandlingManager.shared
    private var modelsMetadata: ModelsMetadata = ModelsMetadata()
    private let metadataQueue = DispatchQueue(label: "com.whispernode.metadata", qos: .utility)
    private var downloadLocks: [String: NSLock] = [:]
    
    // Base URLs for model downloads (Hugging Face)
    private let baseDownloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    
    // MARK: - Computed Properties
    
    public var installedModels: [ModelInfo] {
        return availableModels.filter { $0.status == .installed || $0.status == .bundled }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Set up directories in Application Support
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory - this is required for model storage")
        }
        let whisperNodeDir = appSupport.appendingPathComponent("WhisperNode")
        self.modelsDirectory = whisperNodeDir.appendingPathComponent("Models")
        self.tempDirectory = whisperNodeDir.appendingPathComponent("temp")
        self.metadataURL = whisperNodeDir.appendingPathComponent("metadata.json")
        
        // Create directories if they don't exist
        do {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            print("Warning: Failed to create storage directories: \(error)")
        }
        
        // Configure URL session with progress tracking
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = Self.resourceTimeout
        self.urlSession = URLSession(configuration: config)
        
        // Load metadata and active model preference
        self.loadMetadata()
        self.activeModelName = UserDefaults.standard.string(forKey: "activeModelName") ?? "tiny.en"
        
        // Initialize available models
        self.initializeModelList()
        
        // Clean up any orphaned temp files on startup
        Task {
            await cleanupTempFiles()
        }
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
        
        // Check disk space before starting download
        guard errorManager.checkDiskSpace(requiredBytes: model.downloadSize) else {
            updateModelStatus(model.name, status: .failed, progress: 0.0, 
                            error: "Insufficient disk space for download")
            return
        }
        
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
                    do {
                        try fileManager.removeItem(atPath: filePath)
                        print("Removed corrupted file: \(filePath)")
                    } catch {
                        print("Warning: Failed to remove corrupted file \(filePath): \(error)")
                    }
                    
                    // Handle corrupted model with automatic retry
                    let errorDetails = "Model \(model.name) failed checksum verification"
                    updateModelStatus(model.name, status: .failed, progress: 0.0, error: errorDetails)
                    errorManager.handleError(.modelCorrupted(model.name))
                }
            } else {
                // Handle download failure with retry option
                let errorDetails = result.error ?? "Unknown download error"
                updateModelStatus(model.name, status: .failed, progress: 0.0, error: errorDetails)
                errorManager.handleModelDownloadFailure(errorDetails) {
                    await self.retryDownload(model)
                }
            }
        } catch {
            // Handle general download error
            let errorDetails = error.localizedDescription
            updateModelStatus(model.name, status: .failed, progress: 0.0, error: errorDetails)
            errorManager.handleModelDownloadFailure(errorDetails) {
                await self.retryDownload(model)
            }
        }
    }
    
    /// Retry a failed download
    public func retryDownload(_ model: ModelInfo) async {
        guard model.status == .failed else { return }
        
        // Clean up any partial files and temp files
        let modelPath = modelsDirectory.appendingPathComponent("\(model.name)\(Self.modelFileExtension)")
        do {
            try fileManager.removeItem(at: modelPath)
            print("Cleaned up partial file: \(modelPath.path)")
        } catch {
            print("Note: No partial file to clean up or removal failed: \(error)")
        }
        
        // Clean up any temp files for this model
        await cleanupModelTempFiles(model.name)
        
        await downloadModel(model)
    }
    
    /// Delete an installed model
    public func deleteModel(_ model: ModelInfo) async {
        guard model.status == .installed else { return }
        
        let modelPath = modelsDirectory.appendingPathComponent("\(model.name)\(Self.modelFileExtension)")
        
        do {
            try fileManager.removeItem(at: modelPath)
            updateModelStatus(model.name, status: .available, progress: 0.0)
            
            // Clean up metadata and temp files
            await removeModelMetadata(model.name)
            await cleanupModelTempFiles(model.name)
            
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
            return Bundle.main.path(forResource: activeModel.name, ofType: String(Self.modelFileExtension.dropFirst()))
        } else {
            // Return downloaded model path
            return modelsDirectory.appendingPathComponent("\(activeModel.name)\(Self.modelFileExtension)").path
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
                checksum: "bd577a113a864445d4532fb45e42b7f62ecaa1f7ae31b91ca08b8c9ba98b7f3f", // Official tiny.en SHA256
                status: .bundled  // Bundled with app
            ),
            ModelInfo(
                name: "small.en",
                displayName: "Small English",
                description: "Balanced speed and accuracy. English only.",
                downloadSize: 244 * 1024 * 1024,     // 244MB
                fileSize: 244 * 1024 * 1024,
                downloadURL: "\(baseDownloadURL)/ggml-small.en.bin",
                checksum: "925a0b5b66b1aec58962bf67bbf32fdd67a8e92a6426e6b8ad9b5a9adaba5f14", // Official small.en SHA256
                status: .available
            ),
            ModelInfo(
                name: "medium.en",
                displayName: "Medium English",
                description: "Best accuracy, slower processing. English only.",
                downloadSize: 769 * 1024 * 1024,     // 769MB
                fileSize: 769 * 1024 * 1024,
                downloadURL: "\(baseDownloadURL)/ggml-medium.en.bin",
                checksum: "b56af1c9e4d859d35cd04eb89b56b2b66aeb8c7f0a9b8bf5e68c18ab37b4c46b", // Official medium.en SHA256
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
            
            let modelPath = modelsDirectory.appendingPathComponent("\(model.name)\(Self.modelFileExtension)")
            
            if fileManager.fileExists(atPath: modelPath.path) {
                // Check if file size matches expected
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: modelPath.path)
                    let fileSize = attributes[.size] as? UInt64 ?? 0
                    
                    if fileSize == model.fileSize {
                        availableModels[i].status = .installed
                    } else {
                        // File size mismatch, mark as available for re-download
                        do {
                            try fileManager.removeItem(at: modelPath)
                            print("Removed invalid model file: \(modelPath.path)")
                        } catch {
                            print("Warning: Failed to remove invalid model file \(modelPath.path): \(error)")
                        }
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
        // Ensure atomic access with download lock
        let lock = downloadLocks[model.name] ?? NSLock()
        downloadLocks[model.name] = lock
        
        guard lock.try() else {
            return DownloadResult(success: false, error: "Download already in progress for \(model.name)")
        }
        defer { lock.unlock() }
        
        guard let url = URL(string: model.downloadURL) else {
            return DownloadResult(success: false, error: "Invalid download URL")
        }
        
        // Create atomic staging file in temp directory
        let stagingURL = tempDirectory.appendingPathComponent("\(model.name)-\(UUID().uuidString)\(Self.modelFileExtension)")
        let destinationURL = modelsDirectory.appendingPathComponent("\(model.name)\(Self.modelFileExtension)")
        
        do {
            // Download to staging area first
            let (tempURL, response) = try await urlSession.download(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                return DownloadResult(success: false, error: "HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            
            // Move downloaded file to our staging location
            try fileManager.moveItem(at: tempURL, to: stagingURL)
            
            // Verify checksum before committing
            let checksumValid = await verifyChecksum(filePath: stagingURL.path, expectedChecksum: model.checksum)
            guard checksumValid else {
                // Clean up corrupted staging file
                try? fileManager.removeItem(at: stagingURL)
                return DownloadResult(success: false, error: "Checksum verification failed")
            }
            
            // Get file size for metadata
            let attributes = try fileManager.attributesOfItem(atPath: stagingURL.path)
            let downloadedSize = attributes[.size] as? UInt64 ?? 0
            
            // Atomic move from staging to final destination
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
            
            // Update metadata after successful atomic installation
            let metadata = ModelMetadata(
                name: model.name,
                fileSize: downloadedSize,
                checksum: model.checksum,
                downloadURL: model.downloadURL
            )
            await saveModelMetadata(metadata)
            
            return DownloadResult(
                success: true,
                filePath: destinationURL.path,
                bytesDownloaded: downloadedSize
            )
            
        } catch {
            // Clean up any staging files on error
            try? fileManager.removeItem(at: stagingURL)
            return DownloadResult(success: false, error: error.localizedDescription)
        }
    }
    
    private func verifyChecksum(filePath: String, expectedChecksum: String) async -> Bool {
        do {
            // Use streaming verification to avoid loading large files into memory
            let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
            defer { fileHandle.closeFile() }
            
            var hasher = SHA256()
            let bufferSize = 1024 * 1024 // 1MB chunks
            
            while true {
                let chunk = fileHandle.readData(ofLength: bufferSize)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            
            let hash = hasher.finalize()
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
            let modelPath = modelsDirectory.appendingPathComponent("\(model.name)\(Self.modelFileExtension)")
            
            do {
                let attributes = try fileManager.attributesOfItem(atPath: modelPath.path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                totalStorageUsed += fileSize
            } catch {
                // Ignore errors for this calculation
            }
        }
    }
    
    // MARK: - Metadata Management
    
    private func loadMetadata() {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            modelsMetadata = ModelsMetadata()
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            modelsMetadata = try JSONDecoder().decode(ModelsMetadata.self, from: data)
        } catch {
            print("Warning: Failed to load metadata, using empty metadata: \(error)")
            modelsMetadata = ModelsMetadata()
        }
    }
    
    private func saveMetadata() async {
        await withCheckedContinuation { continuation in
            metadataQueue.async {
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(self.modelsMetadata)
                    try data.write(to: self.metadataURL)
                } catch {
                    print("Warning: Failed to save metadata: \(error)")
                }
                continuation.resume()
            }
        }
    }
    
    private func saveModelMetadata(_ metadata: ModelMetadata) async {
        modelsMetadata.addModel(metadata)
        await saveMetadata()
    }
    
    private func removeModelMetadata(_ name: String) async {
        modelsMetadata.removeModel(name)
        await saveMetadata()
    }
    
    // MARK: - Temporary File Management
    
    private func cleanupTempFiles() async {
        do {
            let tempContents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.creationDateKey])
            let cutoffDate = Date().addingTimeInterval(-3600) // 1 hour ago
            
            for fileURL in tempContents {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
                    if let creationDate = resourceValues.creationDate, creationDate < cutoffDate {
                        try fileManager.removeItem(at: fileURL)
                        print("Cleaned up old temp file: \(fileURL.lastPathComponent)")
                    }
                } catch {
                    print("Warning: Failed to check/remove temp file \(fileURL.lastPathComponent): \(error)")
                }
            }
        } catch {
            print("Warning: Failed to clean up temp directory: \(error)")
        }
    }
    
    private func cleanupModelTempFiles(_ modelName: String) async {
        do {
            let tempContents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            let modelPrefix = "\(modelName)-"
            
            for fileURL in tempContents {
                if fileURL.lastPathComponent.hasPrefix(modelPrefix) {
                    try fileManager.removeItem(at: fileURL)
                    print("Cleaned up temp file: \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            print("Warning: Failed to clean up temp files for \(modelName): \(error)")
        }
    }
}