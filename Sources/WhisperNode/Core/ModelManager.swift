import Foundation
import CryptoKit
import SwiftUI

/// Status of a Whisper model
public enum ModelStatus: Sendable {
    case available      // Available for download
    case downloading    // Currently downloading
    case installed      // Downloaded and verified
    case bundled        // Bundled with the app
    case failed         // Download/verification failed
}

/// Information about a Whisper model
public struct ModelInfo: Sendable {
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
public struct ModelMetadata: Codable, Sendable {
    let name: String
    let version: String
    let downloadedDate: Date
    let fileSize: UInt64
    let checksum: String
    let downloadURL: String
    
    public init(name: String, version: String = "1.0", downloadedDate: Date = Date(), fileSize: UInt64, checksum: String, downloadURL: String) {
        self.name = name
        self.version = version
        self.downloadedDate = downloadedDate
        self.fileSize = fileSize
        self.checksum = checksum
        self.downloadURL = downloadURL
    }
}

/// Container for all model metadata
public struct ModelsMetadata: Codable, Sendable {
    let version: Int
    var models: [String: ModelMetadata] = [:]
    
    public mutating func addModel(_ metadata: ModelMetadata) {
        models[metadata.name] = metadata
    }
    
    public mutating func removeModel(_ name: String) {
        models.removeValue(forKey: name)
    }
    
    public func getModel(_ name: String) -> ModelMetadata? {
        models[name]
    }
    
    public init(version: Int = 1) {
        self.version = version
    }
}

/// Manages Whisper model downloads, storage, and lifecycle
@MainActor
public final class ModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
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
    private static let tempFileCleanupInterval: TimeInterval = 3600 // 1 hour for temp file cleanup
    private static let modelFileExtension = ".bin"
    
    // MARK: - Private Properties
    
    private let modelsDirectory: URL
    private let tempDirectory: URL
    private let metadataURL: URL
    private var urlSession: URLSession!
    /// Download state management
    private struct DownloadState {
        let task: URLSessionDownloadTask
        let continuation: CheckedContinuation<DownloadResult, Never>
        let stagingURL: URL
        let destinationURL: URL
    }

    /// Track active downloads with consolidated state
    private var activeDownloads: [String: DownloadState] = [:]

    private let fileManager = FileManager.default
    private let errorManager = ErrorHandlingManager.shared
    private var modelsMetadata: ModelsMetadata = ModelsMetadata()
    private let metadataQueue = DispatchQueue(label: "com.whispernode.metadata", qos: .utility)
    
    // Base URLs for model downloads (Hugging Face)
    private let baseDownloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    
    // MARK: - Computed Properties
    
    public var installedModels: [ModelInfo] {
        return availableModels.filter { $0.status == .installed || $0.status == .bundled }
    }
    
    // MARK: - Initialization
    
    private override init() {
        // Set up directories in Application Support
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Fallback to temporary directory if Application Support is not accessible
            print("⚠️ [ModelManager] Unable to access Application Support directory, using temporary directory as fallback")
            let tempDir = FileManager.default.temporaryDirectory
            let whisperNodeDir = tempDir.appendingPathComponent("WhisperNode")
            self.modelsDirectory = whisperNodeDir.appendingPathComponent("Models")
            self.tempDirectory = whisperNodeDir.appendingPathComponent("temp")
            self.metadataURL = whisperNodeDir.appendingPathComponent("metadata.json")

            // Continue with initialization using temporary directory
            super.init()
            self.urlSession = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)

            // Try to create directories in temp location
            do {
                try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
                print("✅ [ModelManager] Created fallback directories in temporary location")
            } catch {
                print("❌ [ModelManager] Failed to create fallback directories: \(error)")
                // Initialize with minimal functionality
            }

            // Initialize with degraded functionality
            self.loadMetadata()
            self.activeModelName = UserDefaults.standard.string(forKey: "activeModelName") ?? "tiny.en"
            self.initializeModelList()
            return
        }
        let whisperNodeDir = appSupport.appendingPathComponent("WhisperNode")
        self.modelsDirectory = whisperNodeDir.appendingPathComponent("Models")
        self.tempDirectory = whisperNodeDir.appendingPathComponent("temp")
        self.metadataURL = whisperNodeDir.appendingPathComponent("metadata.json")

        // Configure URL session with progress tracking
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = Self.resourceTimeout

        // Call super.init() before using self
        super.init()

        // Now we can use self
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Create directories if they don't exist
        do {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
            print("✅ [ModelManager] Created models directory: \(modelsDirectory.path)")
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
            print("✅ [ModelManager] Created temp directory: \(tempDirectory.path)")
        } catch {
            print("❌ [ModelManager] Failed to create storage directories: \(error)")
            // Handle directory creation failure gracefully
            ErrorHandlingManager.shared.handleError(.systemResourcesExhausted,
                userContext: "Unable to create required storage directories: \(error.localizedDescription)")
            // Continue with degraded functionality - models will be read-only
            print("⚠️ [ModelManager] Continuing with read-only mode due to directory creation failure")
        }

        // Load metadata and active model preference
        self.loadMetadata()
        self.activeModelName = UserDefaults.standard.string(forKey: "activeModelName") ?? "tiny.en"

        // Initialize available models
        self.initializeModelList()

        // Clean up any orphaned temp files on startup
        Task { [weak self] in
            await self?.cleanupTempFiles()
        }
    }
    
    // MARK: - Public Methods
    
    /// Refresh the list of available models and their status
    @MainActor
    public func refreshModels() async {
        await checkInstalledModels()
        await updateDiskSpace()
        calculateTotalStorageUsed()
    }
    
    /// Download a model with progress tracking and checksum verification
    @MainActor
    public func downloadModel(_ model: ModelInfo) async {
        print("🚀 [ModelManager] Starting download for model: \(model.name)")
        print("📊 [ModelManager] Model details - Size: \(model.downloadSize) bytes, URL: \(model.downloadURL)")

        guard model.status != .downloading else {
            print("⚠️ [ModelManager] Download already in progress for \(model.name)")
            return
        }

        // Check network connectivity first
        print("🌐 [ModelManager] Checking network connectivity...")
        guard await checkNetworkConnectivity() else {
            print("❌ [ModelManager] Network connectivity check failed")
            updateModelStatus(model.name, status: .failed, progress: 0.0,
                            error: "No internet connection available")
            errorManager.handleNetworkConnectionFailure("No internet connection available")
            return
        }
        print("✅ [ModelManager] Network connectivity confirmed")

        // Validate download URL
        print("🔗 [ModelManager] Validating download URL: \(model.downloadURL)")
        guard await validateDownloadURL(model.downloadURL) else {
            print("❌ [ModelManager] Download URL validation failed")
            updateModelStatus(model.name, status: .failed, progress: 0.0,
                            error: "Download URL is not accessible")
            errorManager.handleNetworkConnectionFailure("Download URL is not accessible: \(model.downloadURL)")
            return
        }
        print("✅ [ModelManager] Download URL validated successfully")

        // Check disk space before starting download
        print("💾 [ModelManager] Checking disk space (required: \(model.downloadSize) bytes)...")
        guard errorManager.checkDiskSpace(requiredBytes: model.downloadSize) else {
            print("❌ [ModelManager] Insufficient disk space")
            updateModelStatus(model.name, status: .failed, progress: 0.0,
                            error: "Insufficient disk space for download")
            return
        }
        print("✅ [ModelManager] Disk space check passed")

        // Update model status (this may be redundant if already set by UI, but ensures consistency)
        print("📝 [ModelManager] Setting model status to downloading...")
        updateModelStatus(model.name, status: .downloading, progress: 0.0)
        
        print("⬇️ [ModelManager] Starting downloadWithProgress for \(model.name)...")
        let result = await downloadWithProgress(model)
        print("📋 [ModelManager] Download result - Success: \(result.success), Error: \(result.error ?? "none")")

        if result.success, let filePath = result.filePath {
            print("✅ [ModelManager] Download completed successfully, file at: \(filePath)")
            print("🔍 [ModelManager] Starting checksum verification...")

            // Verify checksum
            if await verifyChecksum(filePath: filePath, expectedChecksum: model.checksum) {
                print("✅ [ModelManager] Checksum verification passed")
                updateModelStatus(model.name, status: .installed, progress: 1.0)
                print("🔄 [ModelManager] Refreshing models list...")
                await refreshModels()
                print("🎉 [ModelManager] Model \(model.name) installation completed successfully!")
            } else {
                print("❌ [ModelManager] Checksum verification failed")
                // Delete corrupted file
                do {
                    try fileManager.removeItem(atPath: filePath)
                    print("🗑️ [ModelManager] Removed corrupted file: \(filePath)")
                } catch {
                    print("⚠️ [ModelManager] Warning: Failed to remove corrupted file \(filePath): \(error)")
                }

                // Handle corrupted model with automatic retry
                let errorDetails = "Model \(model.name) failed checksum verification"
                print("💥 [ModelManager] Setting model status to failed: \(errorDetails)")
                updateModelStatus(model.name, status: .failed, progress: 0.0, error: errorDetails)
                errorManager.handleError(.modelCorrupted(model.name))
            }
        } else {
            // Handle download failure with retry option
            let errorDetails = result.error ?? "Unknown download error"
            print("❌ [ModelManager] Download failed: \(errorDetails)")
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

    /// Immediately update model status for UI responsiveness
    public func updateModelStatusImmediately(_ modelName: String, status: ModelStatus, progress: Double = 0.0, error: String? = nil) {
        updateModelStatus(modelName, status: status, progress: progress, error: error)
    }

    /// Validate network connectivity
    private func checkNetworkConnectivity() async -> Bool {
        // Check connectivity to the actual download server
        guard let url = URL(string: baseDownloadURL) else { return false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5.0

            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            // Fallback to checking a reliable CDN endpoint
            if let cdnURL = URL(string: "https://cdn.jsdelivr.net/") {
                do {
                    let (_, response) = try await URLSession.shared.data(from: cdnURL)
                    return (response as? HTTPURLResponse)?.statusCode == 200
                } catch {
                    return false
                }
            }
            return false
        }
    }

    /// Validate download URL accessibility
    private func validateDownloadURL(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10.0

            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("URL validation failed for \(urlString): \(error.localizedDescription)")
            return false
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
                downloadSize: 487614201,              // Actual size: 487,614,201 bytes
                fileSize: 487614201,
                downloadURL: "\(baseDownloadURL)/ggml-small.en.bin",
                checksum: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d", // Correct SHA256 from actual download
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
        // Check if download is already in progress
        if activeDownloads[model.name] != nil {
            return DownloadResult(success: false, error: "Download already in progress for \(model.name). Please wait for current download to complete.")
        }

        guard let url = URL(string: model.downloadURL) else {
            return DownloadResult(success: false, error: "Invalid download URL")
        }

        // Create atomic staging file in temp directory
        let stagingURL = tempDirectory.appendingPathComponent("\(model.name)-\(UUID().uuidString)\(Self.modelFileExtension)")
        let destinationURL = modelsDirectory.appendingPathComponent("\(model.name)\(Self.modelFileExtension)")

        return await withCheckedContinuation { continuation in
            // Create download task WITHOUT completion handler to enable delegate methods
            let downloadTask = urlSession.downloadTask(with: url)

            // Store consolidated download state
            let downloadState = DownloadState(
                task: downloadTask,
                continuation: continuation,
                stagingURL: stagingURL,
                destinationURL: destinationURL
            )
            activeDownloads[model.name] = downloadState

            print("Starting download for \(model.name) from \(url)")
            print("URLSession delegate: \(urlSession.delegate != nil ? "Set" : "Not set")")

            downloadTask.resume()
        }
    }
    
    private func verifyChecksum(filePath: String, expectedChecksum: String) async -> Bool {
        do {
            print("🔍 [ModelManager] Starting checksum verification")
            print("📁 [ModelManager] File path: \(filePath)")
            print("🎯 [ModelManager] Expected checksum: \(expectedChecksum)")

            // Check if file exists and get its size
            let fileURL = URL(fileURLWithPath: filePath)
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            let fileSize = attributes[.size] as? UInt64 ?? 0
            print("📊 [ModelManager] File size: \(fileSize) bytes")

            // Use streaming verification to avoid loading large files into memory
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { fileHandle.closeFile() }

            var hasher = SHA256()
            let bufferSize = 1024 * 1024 // 1MB chunks
            var totalBytesRead: UInt64 = 0

            print("🔄 [ModelManager] Starting SHA256 calculation...")
            while true {
                let chunk = fileHandle.readData(ofLength: bufferSize)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
                totalBytesRead += UInt64(chunk.count)

                // Progress logging for large files
                if totalBytesRead % (10 * 1024 * 1024) == 0 { // Every 10MB
                    let progress = Double(totalBytesRead) / Double(fileSize) * 100
                    print("📈 [ModelManager] Checksum progress: \(Int(progress))% (\(totalBytesRead)/\(fileSize) bytes)")
                }
            }

            let hash = hasher.finalize()
            let calculatedChecksum = hash.compactMap { String(format: "%02x", $0) }.joined()

            print("✅ [ModelManager] SHA256 calculation complete")
            print("🧮 [ModelManager] Calculated checksum: \(calculatedChecksum)")
            print("🎯 [ModelManager] Expected checksum:   \(expectedChecksum)")
            print("📊 [ModelManager] Total bytes processed: \(totalBytesRead)")

            let isValid = calculatedChecksum.lowercased() == expectedChecksum.lowercased()
            print("🔍 [ModelManager] Checksum match: \(isValid)")

            return isValid
        } catch {
            print("❌ [ModelManager] Checksum verification error: \(error)")
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

    // MARK: - URLSessionDownloadDelegate

    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Calculate progress
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0

        // Debug logging
        print("Download progress: \(Int(progress * 100))% (\(totalBytesWritten)/\(totalBytesExpectedToWrite) bytes)")

        // Update UI on main thread
        Task { @MainActor in
            // Find the model being downloaded
            guard let modelName = self.activeDownloads.first(where: { $0.value.task == downloadTask })?.key else {
                print("Warning: Could not find model name for progress update")
                return
            }
            print("Updating progress for \(modelName): \(Int(progress * 100))%")
            self.updateModelStatus(modelName, status: .downloading, progress: progress)
        }
    }

    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print("📥 [ModelManager] didFinishDownloadingTo called with location: \(location.path)")

        // CRITICAL: URLSession deletes the temp file IMMEDIATELY when this method returns
        // We must synchronously preserve the file before any async operations

        // Create a unique temporary file in our own temp directory to preserve the download
        let preservedTempURL = tempDirectory.appendingPathComponent("download-\(UUID().uuidString).tmp")

        print("🚀 [ModelManager] SYNCHRONOUSLY preserving temp file before URLSession deletes it")
        print("📂 [ModelManager] Preserving from: \(location.path)")
        print("📂 [ModelManager] Preserving to: \(preservedTempURL.path)")

        do {
            // Ensure our temp directory exists
            if !FileManager.default.fileExists(atPath: tempDirectory.path) {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
            }

            // SYNCHRONOUSLY copy the file to our preserved location before URLSession deletes it
            try FileManager.default.copyItem(at: location, to: preservedTempURL)
            print("✅ [ModelManager] Successfully preserved temp file")

            // Now handle the rest asynchronously with our preserved file
            Task { @MainActor in
                await self.handleDownloadCompletion(downloadTask: downloadTask, tempURL: preservedTempURL, error: nil)
            }
        } catch {
            print("❌ [ModelManager] Failed to preserve temp file: \(error)")
            Task { @MainActor in
                await self.handleDownloadCompletion(downloadTask: downloadTask, tempURL: nil, error: error)
            }
        }
    }

    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let downloadTask = task as? URLSessionDownloadTask {
            print("🏁 [ModelManager] didCompleteWithError called with error: \(error?.localizedDescription ?? "none")")
            // Only handle completion if there was an error - successful downloads are handled in didFinishDownloadingTo
            if error != nil {
                Task { @MainActor in
                    await handleDownloadCompletion(downloadTask: downloadTask, tempURL: nil, error: error)
                }
            } else {
                print("✅ [ModelManager] Download completed successfully, already handled in didFinishDownloadingTo")
            }
        }
    }

    /// Handle download completion from URLSessionDownloadDelegate
    @MainActor
    private func handleDownloadCompletion(downloadTask: URLSessionDownloadTask, tempURL: URL?, error: Error?) async {
        print("🏁 [ModelManager] handleDownloadCompletion called")
        print("📍 [ModelManager] TempURL: \(tempURL?.path ?? "nil"), Error: \(error?.localizedDescription ?? "none")")

        // Find the model being downloaded
        guard let modelName = activeDownloads.first(where: { $0.value.task == downloadTask })?.key else {
            print("⚠️ [ModelManager] Warning: Could not find model name for completed download task (likely already processed)")
            print("📊 [ModelManager] Active downloads: \(activeDownloads.keys.joined(separator: ", "))")
            return
        }
        print("🎯 [ModelManager] Found model name: \(modelName)")

        // Check if this download has already been processed (race condition protection)
        guard let downloadState = activeDownloads.removeValue(forKey: modelName) else {
            print("⚠️ [ModelManager] Warning: Download for \(modelName) already processed, skipping duplicate call")
            return
        }

        // Extract download state components
        let continuation = downloadState.continuation
        let stagingURL = downloadState.stagingURL
        let destinationURL = downloadState.destinationURL

        print("✅ [ModelManager] Retrieved download state for \(modelName)")
        print("📁 [ModelManager] Staging URL: \(stagingURL.path)")
        print("📁 [ModelManager] Destination URL: \(destinationURL.path)")
        print("🧹 [ModelManager] Cleaned up download state for \(modelName)")

        // Handle error case
        if let error = error {
            print("Download failed for \(modelName): \(error.localizedDescription)")
            resetModelToAvailable(modelName, error: error.localizedDescription)
            continuation.resume(returning: DownloadResult(success: false, error: error.localizedDescription))
            return
        }

        // Handle missing temp URL
        guard let tempURL = tempURL else {
            let errorMsg = "No temporary file received"
            print("Download failed for \(modelName): \(errorMsg)")
            resetModelToAvailable(modelName, error: errorMsg)
            continuation.resume(returning: DownloadResult(success: false, error: errorMsg))
            return
        }

        // Find the model info for checksum verification
        guard let modelInfo = availableModels.first(where: { $0.name == modelName }) else {
            let errorMsg = "Model info not found for \(modelName)"
            print("Download failed for \(modelName): \(errorMsg)")
            resetModelToAvailable(modelName, error: errorMsg)
            continuation.resume(returning: DownloadResult(success: false, error: errorMsg))
            return
        }

        do {
            print("📂 [ModelManager] Moving preserved file from: \(tempURL.path)")
            print("📂 [ModelManager] Moving preserved file to: \(stagingURL.path)")

            // Ensure the staging directory exists
            let stagingDir = stagingURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: stagingDir.path) {
                print("📁 [ModelManager] Creating staging directory: \(stagingDir.path)")
                try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true, attributes: nil)
            }

            // Verify source file exists
            guard fileManager.fileExists(atPath: tempURL.path) else {
                throw NSError(domain: "ModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Preserved file does not exist: \(tempURL.path)"])
            }

            // Move preserved file to staging location
            try fileManager.moveItem(at: tempURL, to: stagingURL)
            print("✅ [ModelManager] Successfully moved preserved file to staging location")

            let fileToVerify = stagingURL

            // Verify checksum before committing
            print("🔍 [ModelManager] Verifying checksum for file: \(fileToVerify.path)")
            let checksumValid = await verifyChecksum(filePath: fileToVerify.path, expectedChecksum: modelInfo.checksum)
            guard checksumValid else {
                // Clean up corrupted staging file
                try? fileManager.removeItem(at: fileToVerify)
                let errorMsg = "Checksum verification failed"
                print("❌ [ModelManager] Download failed for \(modelName): \(errorMsg)")
                resetModelToAvailable(modelName, error: errorMsg)
                continuation.resume(returning: DownloadResult(success: false, error: errorMsg))
                return
            }
            print("✅ [ModelManager] Checksum verification passed")

            // Get file size for metadata
            let attributes = try fileManager.attributesOfItem(atPath: fileToVerify.path)
            let downloadedSize = attributes[.size] as? UInt64 ?? 0

            // Atomic move from staging to final destination
            print("📁 [ModelManager] Moving from staging to final destination: \(destinationURL.path)")
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
                print("🗑️ [ModelManager] Removed existing file at destination")
            }
            try fileManager.moveItem(at: fileToVerify, to: destinationURL)
            print("✅ [ModelManager] Successfully moved to final destination")

            // Update metadata after successful atomic installation
            let metadata = ModelMetadata(
                name: modelName,
                fileSize: downloadedSize,
                checksum: modelInfo.checksum,
                downloadURL: modelInfo.downloadURL
            )
            await saveModelMetadata(metadata)

            // Update status to installed with 100% progress
            updateModelStatus(modelName, status: .installed, progress: 1.0)

            continuation.resume(returning: DownloadResult(
                success: true,
                filePath: destinationURL.path,
                bytesDownloaded: downloadedSize
            ))

        } catch {
            // Clean up any staging files on error
            try? fileManager.removeItem(at: stagingURL)
            let errorMsg = error.localizedDescription
            print("Download failed for \(modelName): \(errorMsg)")
            resetModelToAvailable(modelName, error: errorMsg)
            continuation.resume(returning: DownloadResult(success: false, error: errorMsg))
        }
    }

    /// Reset a model to available status after download failure
    @MainActor
    private func resetModelToAvailable(_ modelName: String, error: String) {
        if let index = availableModels.firstIndex(where: { $0.name == modelName }) {
            // Reset to available status so user can retry
            availableModels[index].status = .available
            availableModels[index].downloadProgress = 0.0
            availableModels[index].errorMessage = error
            print("Reset \(modelName) to available status after error: \(error)")
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
        // @MainActor isolation provides thread safety
        
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            modelsMetadata = ModelsMetadata()
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            let loadedMetadata = try JSONDecoder().decode(ModelsMetadata.self, from: data)
            
            // Handle metadata schema migrations
            if loadedMetadata.version < 1 {
                print("Migrating metadata from version \(loadedMetadata.version) to 1")
                // For now, just create new metadata - in future versions, implement actual migration
                modelsMetadata = ModelsMetadata(version: 1)
            } else {
                modelsMetadata = loadedMetadata
            }
        } catch {
            print("Warning: Failed to load metadata, will rebuild from disk on next operation: \(error)")
            // Initialize with empty metadata, rebuild will happen async later
            modelsMetadata = ModelsMetadata()
        }
    }
    
    private func saveMetadata() async {
        // Use actor isolation for thread safety
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(modelsMetadata)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            print("Warning: Failed to save metadata: \(error)")
        }
    }
    
    private func saveModelMetadata(_ metadata: ModelMetadata) async {
        // Use actor isolation for thread safety
        modelsMetadata.addModel(metadata)
        await saveMetadata()
    }
    
    private func removeModelMetadata(_ name: String) async {
        // Use actor isolation for thread safety
        modelsMetadata.removeModel(name)
        await saveMetadata()
    }
    
    /// Rebuild metadata from disk if metadata.json is corrupted or missing
    private func rebuildMetadataFromDisk() async {
        // Use actor isolation for thread safety
        var rebuiltMetadata = ModelsMetadata()
        
        do {
            let modelFiles = try fileManager.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            
            for fileURL in modelFiles where fileURL.pathExtension == "bin" {
                let modelName = fileURL.deletingPathExtension().lastPathComponent
                
                // Get file attributes
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let fileSize = UInt64(resourceValues.fileSize ?? 0)
                let creationDate = resourceValues.creationDate ?? Date()
                
                // Find matching model info for checksum and URL
                if let modelInfo = availableModels.first(where: { $0.name == modelName }) {
                    let metadata = ModelMetadata(
                        name: modelName,
                        downloadedDate: creationDate,
                        fileSize: fileSize,
                        checksum: modelInfo.checksum,
                        downloadURL: modelInfo.downloadURL
                    )
                    rebuiltMetadata.addModel(metadata)
                }
            }
            
            modelsMetadata = rebuiltMetadata
            print("Rebuilt metadata for \(rebuiltMetadata.models.count) models from disk")
            
        } catch {
            print("Warning: Failed to rebuild metadata from disk: \(error)")
            modelsMetadata = ModelsMetadata()
        }
    }
    
    // MARK: - Temporary File Management
    
    private func cleanupTempFiles() async {
        do {
            let tempContents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.creationDateKey])
            let cutoffDate = Date().addingTimeInterval(-Self.tempFileCleanupInterval)
            
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
            
            for fileURL in tempContents where fileURL.lastPathComponent.hasPrefix(modelPrefix) {
                try fileManager.removeItem(at: fileURL)
                print("Cleaned up temp file: \(fileURL.lastPathComponent)")
            }
        } catch {
            print("Warning: Failed to clean up temp files for \(modelName): \(error)")
        }
    }
}
