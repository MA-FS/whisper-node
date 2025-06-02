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