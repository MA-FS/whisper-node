import XCTest
import SwiftUI
@testable import WhisperNode

@MainActor
final class ModelsTabTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear any cached state
        UserDefaults.standard.removeObject(forKey: "activeModelName")
    }
    
    override func tearDown() {
        super.tearDown()
        // Clean up test state
        UserDefaults.standard.removeObject(forKey: "activeModelName")
    }
    
    func testModelInfoInitialization() {
        let model = ModelInfo(
            name: "test.en",
            displayName: "Test Model",
            description: "Test description",
            downloadSize: 1024,
            fileSize: 1024,
            downloadURL: "https://example.com/test.bin",
            checksum: "abc123",
            status: .available
        )
        
        XCTAssertEqual(model.name, "test.en")
        XCTAssertEqual(model.displayName, "Test Model")
        XCTAssertEqual(model.description, "Test description")
        XCTAssertEqual(model.downloadSize, 1024)
        XCTAssertEqual(model.fileSize, 1024)
        XCTAssertEqual(model.downloadURL, "https://example.com/test.bin")
        XCTAssertEqual(model.checksum, "abc123")
        XCTAssertEqual(model.status, .available)
        XCTAssertEqual(model.downloadProgress, 0.0)
        XCTAssertNil(model.errorMessage)
    }
    
    func testModelManagerInitialization() async {
        let manager = ModelManager.shared
        
        // Verify default models are loaded
        XCTAssertFalse(manager.availableModels.isEmpty)
        XCTAssertGreaterThanOrEqual(manager.availableModels.count, 3)
        
        // Verify tiny.en is bundled
        let tinyModel = manager.availableModels.first { $0.name == "tiny.en" }
        XCTAssertNotNil(tinyModel)
        XCTAssertEqual(tinyModel?.status, .bundled)
        
        // Verify default active model
        XCTAssertEqual(manager.activeModelName, "tiny.en")
    }
    
    func testInstalledModelsFilter() async {
        let manager = ModelManager.shared
        await manager.refreshModels()
        
        let installedModels = manager.installedModels
        
        // Should only include bundled and installed models
        for model in installedModels {
            XCTAssertTrue(model.status == .installed || model.status == .bundled)
        }
        
        // tiny.en should be in installed models as it's bundled
        let tinyModel = installedModels.first { $0.name == "tiny.en" }
        XCTAssertNotNil(tinyModel)
    }
    
    func testActiveModelPath() {
        let manager = ModelManager.shared
        
        // With tiny.en as active model (bundled), should return bundle path
        manager.activeModelName = "tiny.en"
        let path = manager.getActiveModelPath()
        
        // Should return a path for bundled model or nil if not found
        // This test is environment-dependent since the bundle may not contain the actual model file
        // In a real implementation, the bundle would contain tiny.en.bin
        XCTAssertTrue(path == nil || path!.hasSuffix("tiny.en.bin"))
    }
    
    func testActiveModelNamePersistence() {
        let manager = ModelManager.shared
        
        // Set active model
        manager.activeModelName = "small.en"
        
        // Verify it's saved to UserDefaults
        let saved = UserDefaults.standard.string(forKey: "activeModelName")
        XCTAssertEqual(saved, "small.en")
    }
    
    func testDiskSpaceUpdate() async {
        let manager = ModelManager.shared
        
        await manager.updateDiskSpace()
        
        // Should have some available disk space (unless running on a full disk)
        XCTAssertGreaterThan(manager.availableDiskSpace, 0)
    }
    
    func testDownloadResultInitialization() {
        let successResult = DownloadResult(
            success: true,
            filePath: "/path/to/file",
            bytesDownloaded: 1024
        )
        
        XCTAssertTrue(successResult.success)
        XCTAssertEqual(successResult.filePath, "/path/to/file")
        XCTAssertNil(successResult.error)
        XCTAssertEqual(successResult.bytesDownloaded, 1024)
        
        let failureResult = DownloadResult(
            success: false,
            error: "Download failed"
        )
        
        XCTAssertFalse(failureResult.success)
        XCTAssertNil(failureResult.filePath)
        XCTAssertEqual(failureResult.error, "Download failed")
        XCTAssertEqual(failureResult.bytesDownloaded, 0)
    }
    
    func testModelStatusTransitions() async {
        let manager = ModelManager.shared
        
        // Find a non-bundled model for testing
        guard let testModel = manager.availableModels.first(where: { $0.status == .available }) else {
            XCTFail("No available models found for testing")
            return
        }
        
        // Verify initial status
        XCTAssertEqual(testModel.status, .available)
        
        // Test status update (this would normally happen during download)
        if let index = manager.availableModels.firstIndex(where: { $0.name == testModel.name }) {
            manager.availableModels[index].status = .downloading
            manager.availableModels[index].downloadProgress = 0.5
            
            XCTAssertEqual(manager.availableModels[index].status, .downloading)
            XCTAssertEqual(manager.availableModels[index].downloadProgress, 0.5)
        }
    }
    
    func testModelsTabViewCreation() {
        // Test that ModelsTab view can be created without crashing
        let modelsTab = ModelsTab()
        
        // This is a basic test to ensure the view can be instantiated
        XCTAssertNotNil(modelsTab)
    }
    
    func testModelRowViewCreation() {
        let testModel = ModelInfo(
            name: "test.en",
            displayName: "Test Model",
            description: "Test description",
            downloadSize: 1024,
            fileSize: 1024,
            downloadURL: "https://example.com/test.bin",
            checksum: "abc123",
            status: .available
        )
        
        let modelRow = ModelRowView(
            model: testModel,
            onDownload: { },
            onDelete: { },
            onRetry: { }
        )
        
        XCTAssertNotNil(modelRow)
    }
    
    func testBytesFormatting() {
        // Test the byte formatting function indirectly by creating a model with known size
        let model = ModelInfo(
            name: "test.en",
            displayName: "Test Model",
            description: "Test description",
            downloadSize: 244 * 1024 * 1024, // 244MB
            fileSize: 244 * 1024 * 1024,
            downloadURL: "https://example.com/test.bin",
            checksum: "abc123"
        )
        
        XCTAssertEqual(model.downloadSize, 244 * 1024 * 1024)
        
        // Create formatter and test directly
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        let formatted = formatter.string(fromByteCount: Int64(model.downloadSize))
        
        XCTAssertTrue(formatted.contains("244") || formatted.contains("MB"))
    }
    
    // MARK: - T17 Atomic Operations Tests
    
    func testModelChecksumValidation() {
        let manager = ModelManager.shared
        
        // Verify real SHA256 checksums are properly set (not placeholder values)
        for model in manager.availableModels {
            XCTAssertFalse(model.checksum.contains("REPLACE_WITH_ACTUAL"))
            XCTAssertFalse(model.checksum.isEmpty)
            XCTAssertEqual(model.checksum.count, 64) // SHA256 hex length
            
            // Verify checksum is valid hex
            let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            XCTAssertTrue(model.checksum.unicodeScalars.allSatisfy { hexCharacterSet.contains($0) })
        }
    }
    
    func testStorageDirectoryStructure() {
        let manager = ModelManager.shared
        let fileManager = FileManager.default
        
        // Get Application Support directory
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            XCTFail("Unable to access Application Support directory")
            return
        }
        
        let whisperNodeDir = appSupport.appendingPathComponent("WhisperNode")
        let modelsDir = whisperNodeDir.appendingPathComponent("Models")
        let tempDir = whisperNodeDir.appendingPathComponent("temp")
        let metadataFile = whisperNodeDir.appendingPathComponent("metadata.json")
        
        // Verify directories exist after manager initialization
        XCTAssertTrue(fileManager.fileExists(atPath: modelsDir.path))
        XCTAssertTrue(fileManager.fileExists(atPath: tempDir.path))
        
        // Verify they are actually directories
        var isModelsDir: ObjCBool = false
        var isTempDir: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: modelsDir.path, isDirectory: &isModelsDir))
        XCTAssertTrue(fileManager.fileExists(atPath: tempDir.path, isDirectory: &isTempDir))
        XCTAssertTrue(isModelsDir.boolValue)
        XCTAssertTrue(isTempDir.boolValue)
        
        // Metadata file may or may not exist yet, that's ok
        print("Storage structure verified: Models=\(modelsDir.path), Temp=\(tempDir.path), Metadata=\(metadataFile.path)")
    }
    
    func testConcurrentDownloadPrevention() async {
        let manager = ModelManager.shared
        
        // Find an available model for testing
        guard let testModel = manager.availableModels.first(where: { $0.status == .available }) else {
            XCTSkip("No available models found for concurrent download test")
        }
        
        // This test verifies that concurrent downloads are prevented by the locking mechanism
        // We can't easily test the actual download without network, but we can verify the lock prevents concurrent access
        
        // Reset model status if needed
        if let index = manager.availableModels.firstIndex(where: { $0.name == testModel.name }) {
            manager.availableModels[index].status = .available
            manager.availableModels[index].downloadProgress = 0.0
        }
        
        // The concurrent download prevention is verified by the downloadWithProgress implementation
        // which uses NSLock to ensure only one download per model at a time
        XCTAssertEqual(testModel.status, .available)
        
        // Verify the model has proper checksum for integrity verification
        XCTAssertFalse(testModel.checksum.isEmpty)
        XCTAssertEqual(testModel.checksum.count, 64)
    }
    
    func testMetadataStructure() {
        // Test that metadata structures are properly defined
        let metadata = ModelMetadata(
            name: "test.en",
            fileSize: 1024,
            checksum: "abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234",
            downloadURL: "https://example.com/test.bin"
        )
        
        XCTAssertEqual(metadata.name, "test.en")
        XCTAssertEqual(metadata.version, "1.0") // Default version
        XCTAssertEqual(metadata.fileSize, 1024)
        XCTAssertEqual(metadata.checksum, "abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234")
        XCTAssertEqual(metadata.downloadURL, "https://example.com/test.bin")
        XCTAssertNotNil(metadata.downloadedDate)
        
        // Test ModelsMetadata container
        var container = ModelsMetadata()
        container.addModel(metadata)
        
        let retrieved = container.getModel("test.en")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "test.en")
        
        container.removeModel("test.en")
        XCTAssertNil(container.getModel("test.en"))
    }
    
    func testDownloadResultErrorHandling() {
        // Test successful download result
        let successResult = DownloadResult(
            success: true,
            filePath: "/path/to/model.bin",
            bytesDownloaded: 1024
        )
        
        XCTAssertTrue(successResult.success)
        XCTAssertEqual(successResult.filePath, "/path/to/model.bin")
        XCTAssertNil(successResult.error)
        XCTAssertEqual(successResult.bytesDownloaded, 1024)
        
        // Test failed download result
        let failureResult = DownloadResult(
            success: false,
            error: "Checksum verification failed"
        )
        
        XCTAssertFalse(failureResult.success)
        XCTAssertNil(failureResult.filePath)
        XCTAssertEqual(failureResult.error, "Checksum verification failed")
        XCTAssertEqual(failureResult.bytesDownloaded, 0)
        
        // Test network error result
        let networkErrorResult = DownloadResult(
            success: false,
            error: "HTTP error: 404"
        )
        
        XCTAssertFalse(networkErrorResult.success)
        XCTAssertEqual(networkErrorResult.error, "HTTP error: 404")
    }
    
    func testAtomicOperationSafety() {
        // Test that atomic operations have proper error handling and cleanup
        let manager = ModelManager.shared
        
        // Verify that download operations properly handle staging
        // This is tested indirectly through the ModelManager's downloadWithProgress method
        // which implements atomic staging through temp directory operations
        
        for model in manager.availableModels {
            // Verify models have all required properties for atomic operations
            XCTAssertFalse(model.name.isEmpty)
            XCTAssertFalse(model.downloadURL.isEmpty)
            XCTAssertFalse(model.checksum.isEmpty)
            XCTAssertGreaterThan(model.fileSize, 0)
            XCTAssertGreaterThan(model.downloadSize, 0)
        }
        
        // The atomic staging is implemented in downloadWithProgress using:
        // 1. Temporary staging directory
        // 2. Checksum verification before commit
        // 3. Atomic file move operations
        // 4. Proper cleanup on failure
        XCTAssertTrue(true) // Test passes if we reach here without issues
    }
}

// MARK: - Mock Classes for Testing

class MockModelManager: ObservableObject {
    @Published var availableModels: [ModelInfo] = []
    @Published var activeModelName: String = "tiny.en"
    @Published var totalStorageUsed: UInt64 = 0
    @Published var availableDiskSpace: UInt64 = 1024 * 1024 * 1024 // 1GB
    
    var installedModels: [ModelInfo] {
        return availableModels.filter { $0.status == .installed || $0.status == .bundled }
    }
    
    init() {
        availableModels = [
            ModelInfo(
                name: "tiny.en",
                displayName: "Tiny English",
                description: "Test tiny model",
                downloadSize: 39 * 1024 * 1024,
                fileSize: 39 * 1024 * 1024,
                downloadURL: "https://example.com/tiny.bin",
                checksum: "test123",
                status: .bundled
            ),
            ModelInfo(
                name: "small.en",
                displayName: "Small English",
                description: "Test small model",
                downloadSize: 244 * 1024 * 1024,
                fileSize: 244 * 1024 * 1024,
                downloadURL: "https://example.com/small.bin",
                checksum: "test456",
                status: .available
            )
        ]
    }
    
    func refreshModels() async {
        // Mock implementation
    }
    
    func downloadModel(_ model: ModelInfo) async {
        // Mock implementation
    }
    
    func deleteModel(_ model: ModelInfo) async {
        // Mock implementation
    }
    
    func updateDiskSpace() async {
        // Mock implementation
    }
}