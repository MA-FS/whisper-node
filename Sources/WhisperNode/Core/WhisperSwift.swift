import Foundation
import WhisperBridge

/// Performance metrics for monitoring whisper operations
public struct WhisperPerformanceMetrics {
    public let memoryUsage: UInt64      // Current memory usage in bytes
    public let averageCpuUsage: Float   // Average CPU usage percentage
    public let isDowngradeNeeded: Bool  // Whether model downgrade is recommended
    public let suggestedModel: String?  // Suggested smaller model if applicable
}

/// Swift wrapper for Rust whisper FFI with enhanced memory management
public class WhisperSwift {
    private var handle: OpaquePointer?
    private let modelPath: String
    private var lastCleanup: Date = Date()
    private let cleanupInterval: TimeInterval = 30.0 // Cleanup every 30 seconds
    
    public init?(modelPath: String) {
        self.modelPath = modelPath
        
        guard let cPath = modelPath.cString(using: .utf8) else {
            return nil
        }
        
        #if RUST_FFI_ENABLED
        handle = whisper_init(cPath)
        guard handle != nil else {
            return nil
        }
        #else
        handle = OpaquePointer(bitPattern: 0x1) // Placeholder non-null handle
        #endif
    }
    
    deinit {
        if let handle = handle {
            #if RUST_FFI_ENABLED
            whisper_free(handle)
            #endif
        }
    }
    
    /// Transcribe audio data with automatic memory management
    /// - Parameter audioData: Array of f32 audio samples at 16kHz mono
    /// - Returns: Transcribed text or nil if failed
    public func transcribe(audioData: [Float]) -> String? {
        guard let handle = handle else { return nil }
        guard !audioData.isEmpty else { return nil }
        
        // Perform periodic memory cleanup
        performPeriodicCleanup()
        
        #if RUST_FFI_ENABLED
        let result = audioData.withUnsafeBufferPointer { buffer in
            whisper_transcribe(handle, buffer.baseAddress, buffer.count)
        }
        
        defer {
            // Clean up memory
            if result.text != nil {
                whisper_free_string(result.text)
            }
            if result.error != nil {
                whisper_free_string(result.error)
            }
        }
        
        guard result.success else {
            if let errorPtr = result.error {
                let errorString = String(cString: errorPtr)
                print("Whisper transcription error: \(errorString)")
            }
            return nil
        }
        
        guard let textPtr = result.text else {
            return nil
        }
        
        let transcribedText = String(cString: textPtr)
        
        // Check if model downgrade is recommended
        if whisper_check_downgrade_needed(handle) {
            if let suggestedPtr = whisper_get_suggested_model(handle) {
                let suggested = String(cString: suggestedPtr)
                whisper_free_string(suggestedPtr)
                print("Whisper: High CPU usage detected, consider switching to \(suggested) model")
            }
        }
        
        return transcribedText
        #else
        // Placeholder implementation
        return "FFI placeholder - Rust integration pending"
        #endif
    }
    
    /// Get current performance metrics
    /// - Returns: Performance metrics including memory usage and CPU stats
    public func getPerformanceMetrics() -> WhisperPerformanceMetrics {
        guard let handle = handle else {
            return WhisperPerformanceMetrics(
                memoryUsage: 0,
                averageCpuUsage: 0,
                isDowngradeNeeded: false,
                suggestedModel: nil
            )
        }
        
        #if RUST_FFI_ENABLED
        let memoryUsage = whisper_get_memory_usage()
        let avgCpuUsage = whisper_get_avg_cpu_usage()
        let isDowngradeNeeded = whisper_check_downgrade_needed(handle)
        
        var suggestedModel: String?
        if isDowngradeNeeded {
            if let suggestedPtr = whisper_get_suggested_model(handle) {
                suggestedModel = String(cString: suggestedPtr)
                whisper_free_string(suggestedPtr)
            }
        }
        
        return WhisperPerformanceMetrics(
            memoryUsage: memoryUsage,
            averageCpuUsage: avgCpuUsage,
            isDowngradeNeeded: isDowngradeNeeded,
            suggestedModel: suggestedModel
        )
        #else
        return WhisperPerformanceMetrics(
            memoryUsage: 50 * 1024 * 1024, // 50MB placeholder
            averageCpuUsage: 25.0,
            isDowngradeNeeded: false,
            suggestedModel: nil
        )
        #endif
    }
    
    /// Force memory cleanup by unloading idle models
    /// - Returns: True if cleanup was successful
    @discardableResult
    public func cleanupMemory() -> Bool {
        #if RUST_FFI_ENABLED
        return whisper_cleanup_memory()
        #else
        return true
        #endif
    }
    
    /// Perform periodic memory cleanup if needed
    private func performPeriodicCleanup() {
        let now = Date()
        if now.timeIntervalSince(lastCleanup) > cleanupInterval {
            cleanupMemory()
            lastCleanup = now
        }
    }
}

/// Result structure for transcription with performance metrics
public struct TranscriptionResult {
    public let text: String
    public let success: Bool
    public let error: String?
    public let duration: TimeInterval?
    public let metrics: WhisperPerformanceMetrics?
    
    public init(text: String = "", success: Bool, error: String? = nil, duration: TimeInterval? = nil, metrics: WhisperPerformanceMetrics? = nil) {
        self.text = text
        self.success = success
        self.error = error
        self.duration = duration
        self.metrics = metrics
    }
}

/// Enhanced whisper wrapper with async support and performance monitoring
public actor WhisperEngine {
    private let whisper: WhisperSwift
    private var performanceHistory: [WhisperPerformanceMetrics] = []
    private let maxHistorySize = 100
    
    public init?(modelPath: String) {
        guard let whisper = WhisperSwift(modelPath: modelPath) else {
            return nil
        }
        self.whisper = whisper
    }
    
    /// Async transcription with performance monitoring
    public func transcribe(audioData: [Float]) async -> TranscriptionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        if let text = whisper.transcribe(audioData: audioData) {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let metrics = whisper.getPerformanceMetrics()
            
            recordPerformanceMetrics(metrics)
            
            return TranscriptionResult(
                text: text,
                success: true,
                duration: duration,
                metrics: metrics
            )
        } else {
            return TranscriptionResult(
                success: false,
                error: "Transcription failed"
            )
        }
    }
    
    /// Get current performance metrics
    public func getCurrentMetrics() -> WhisperPerformanceMetrics {
        return whisper.getPerformanceMetrics()
    }
    
    /// Get performance history for analysis
    public func getPerformanceHistory() -> [WhisperPerformanceMetrics] {
        return performanceHistory
    }
    
    /// Force memory cleanup
    @discardableResult
    public func cleanupMemory() -> Bool {
        return whisper.cleanupMemory()
    }
    
    /// Check if performance indicates model downgrade is needed
    public func shouldDowngradeModel() -> (needed: Bool, suggestedModel: String?) {
        let metrics = whisper.getPerformanceMetrics()
        return (metrics.isDowngradeNeeded, metrics.suggestedModel)
    }
    
    /// Get average performance over recent operations
    public func getAveragePerformance() -> (avgCpu: Float, avgMemory: UInt64) {
        guard !performanceHistory.isEmpty else {
            return (0.0, 0)
        }
        
        let avgCpu = performanceHistory.map { $0.averageCpuUsage }.reduce(0, +) / Float(performanceHistory.count)
        let avgMemory = performanceHistory.map { $0.memoryUsage }.reduce(0, +) / UInt64(performanceHistory.count)
        
        return (avgCpu, avgMemory)
    }
    
    /// Record performance metrics for historical analysis
    private func recordPerformanceMetrics(_ metrics: WhisperPerformanceMetrics) {
        performanceHistory.append(metrics)
        
        // Keep only recent history
        if performanceHistory.count > maxHistorySize {
            performanceHistory.removeFirst()
        }
    }
}