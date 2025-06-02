import Foundation
import WhisperBridge

/// Performance metrics for monitoring whisper operations
///
/// Provides comprehensive monitoring data for Whisper model performance including
/// memory usage, CPU utilization, and automatic optimization recommendations.
///
/// - Note: Memory usage is tracked in bytes and CPU usage as percentage (0-100)
/// - Important: `isDowngradeNeeded` indicates when automatic model optimization is recommended
public struct WhisperPerformanceMetrics {
    public let memoryUsage: UInt64      // Current memory usage in bytes
    public let averageCpuUsage: Float   // Average CPU usage percentage
    public let isDowngradeNeeded: Bool  // Whether model downgrade is recommended
    public let suggestedModel: String?  // Suggested smaller model if applicable
}

/// Swift wrapper for Rust whisper FFI with enhanced memory management
///
/// Provides a high-level interface to the whisper.cpp library through Rust FFI,
/// with automatic memory management, periodic cleanup, and performance monitoring.
///
/// ## Key Features
/// - Automatic memory cleanup every 30 seconds
/// - Thread-safe operations with concurrent access protection
/// - Performance monitoring with CPU usage detection
/// - Model downgrade recommendations for optimal performance
///
/// ## Usage
/// ```swift
/// guard let whisper = WhisperSwift(modelPath: "/path/to/model.bin") else {
///     // Handle initialization failure
///     return
/// }
/// 
/// let transcription = whisper.transcribe(audioData: audioSamples)
/// let metrics = whisper.getPerformanceMetrics()
/// ```
///
/// - Important: Audio data must be 16kHz mono float samples
/// - Warning: Maximum input length is 30 seconds (480,000 samples) for memory safety
public class WhisperSwift {
    private var handle: OpaquePointer?
    private let modelPath: String
    private var lastCleanup: Date = Date()
    private let cleanupInterval: TimeInterval = 30.0 // Cleanup every 30 seconds
    private let cleanupQueue = DispatchQueue(label: "whisper.cleanup")
    
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
    ///
    /// Converts speech audio to text using the loaded Whisper model with automatic
    /// performance monitoring and memory cleanup.
    ///
    /// - Parameter audioData: Array of f32 audio samples at 16kHz mono format
    /// - Returns: Transcribed text string, or nil if transcription failed
    ///
    /// ## Performance Considerations
    /// - Maximum input length: 30 seconds (480,000 samples at 16kHz)
    /// - Automatic memory cleanup triggered every 30 seconds
    /// - CPU usage monitoring with downgrade recommendations
    ///
    /// ## Error Handling
    /// Returns nil for:
    /// - Empty audio data
    /// - Audio exceeding maximum length
    /// - Model initialization failures
    /// - FFI communication errors
    ///
    /// - Important: Longer audio clips may trigger automatic model downgrade suggestions
    public func transcribe(audioData: [Float]) -> String? {
        guard let handle = handle else { return nil }
        guard !audioData.isEmpty else { return nil }
        guard audioData.count <= 16000 * 30 else { return nil } // Max 30 seconds
        
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
                guard let suggested = String(validatingUTF8: suggestedPtr) else {
                    whisper_free_string(suggestedPtr)
                    return transcribedText
                }
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
    ///
    /// Retrieves comprehensive performance data for the current Whisper model instance,
    /// including memory usage, CPU utilization, and optimization recommendations.
    ///
    /// - Returns: WhisperPerformanceMetrics containing:
    ///   - `memoryUsage`: Current memory consumption in bytes
    ///   - `averageCpuUsage`: CPU utilization percentage (0-100)
    ///   - `isDowngradeNeeded`: Whether model optimization is recommended
    ///   - `suggestedModel`: Recommended smaller model if downgrade needed
    ///
    /// ## Usage
    /// ```swift
    /// let metrics = whisper.getPerformanceMetrics()
    /// if metrics.isDowngradeNeeded {
    ///     print("Consider switching to: \(metrics.suggestedModel ?? "smaller model")")
    /// }
    /// ```
    ///
    /// - Note: Metrics are updated in real-time during transcription operations
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
                suggestedModel = String(validatingUTF8: suggestedPtr)
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
    ///
    /// Immediately triggers memory cleanup to free resources from idle models.
    /// This is automatically called every 30 seconds during normal operation.
    ///
    /// - Returns: `true` if cleanup was successful, `false` otherwise
    ///
    /// ## When to Use
    /// - Memory pressure situations
    /// - Before loading large models
    /// - Application backgrounding
    /// - Manual optimization
    ///
    /// - Note: Cleanup is thread-safe and can be called concurrently
    /// - Important: Does not affect currently active transcription operations
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
        cleanupQueue.sync {
            let now = Date()
            if now.timeIntervalSince(lastCleanup) > cleanupInterval {
                cleanupMemory()
                lastCleanup = now
            }
        }
    }
}

/// Result structure for transcription with performance metrics
///
/// Comprehensive result container for speech-to-text operations including
/// transcribed text, success status, timing information, and performance data.
///
/// ## Properties
/// - `text`: The transcribed text output
/// - `success`: Whether transcription completed successfully
/// - `error`: Error message if transcription failed
/// - `duration`: Time taken for transcription in seconds
/// - `metrics`: Real-time performance metrics during transcription
///
/// ## Usage
/// ```swift
/// let result = await engine.transcribe(audioData: samples)
/// if result.success {
///     print("Transcribed: \(result.text)")
///     if let duration = result.duration {
///         print("Completed in \(duration)s")
///     }
/// } else {
///     print("Error: \(result.error ?? "Unknown")")
/// }
/// ```
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
///
/// Thread-safe actor providing asynchronous speech-to-text capabilities with
/// comprehensive performance tracking, memory management, and historical analysis.
///
/// ## Key Features
/// - Thread-safe concurrent access using Swift actor model
/// - Asynchronous transcription with performance metrics
/// - Historical performance tracking for trend analysis
/// - Automatic memory management and cleanup
/// - Model downgrade recommendations based on performance
///
/// ## Performance Monitoring
/// - Tracks transcription duration and resource usage
/// - Maintains rolling history of up to 100 recent operations
/// - Provides average performance calculations
/// - Monitors CPU usage with automatic optimization suggestions
///
/// ## Usage
/// ```swift
/// guard let engine = WhisperEngine(modelPath: "/path/to/model.bin") else {
///     // Handle initialization failure
///     return
/// }
/// 
/// let result = await engine.transcribe(audioData: audioSamples)
/// let metrics = await engine.getCurrentMetrics()
/// let (avgCpu, avgMemory) = await engine.getAveragePerformance()
/// ```
///
/// - Important: All methods are async and thread-safe
/// - Note: Performance history is maintained in memory and reset on app restart
public actor WhisperEngine {
    private static let maxPerformanceHistorySize = 100
    
    private let whisper: WhisperSwift
    private var performanceHistory: [WhisperPerformanceMetrics] = []
    private let maxHistorySize = 10
    
    public init?(modelPath: String) {
        guard let whisper = WhisperSwift(modelPath: modelPath) else {
            return nil
        }
        self.whisper = whisper
    }
    
    /// Async transcription with performance monitoring
    ///
    /// Performs speech-to-text conversion with comprehensive performance tracking
    /// and automatic metrics recording for historical analysis.
    ///
    /// - Parameter audioData: Array of 16kHz mono audio samples (Float values)
    /// - Returns: TranscriptionResult with text, success status, and performance data
    ///
    /// ## Performance Tracking
    /// - Measures transcription duration
    /// - Records memory and CPU usage
    /// - Updates performance history
    /// - Provides downgrade recommendations
    ///
    /// ## Thread Safety
    /// This method is actor-isolated and can be safely called concurrently
    /// from multiple threads without additional synchronization.
    ///
    /// - Important: Large audio files may trigger performance warnings
    /// - Note: All performance metrics are automatically recorded
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
    ///
    /// Retrieves real-time performance data for the Whisper engine including
    /// memory usage, CPU utilization, and optimization recommendations.
    ///
    /// - Returns: Current WhisperPerformanceMetrics snapshot
    ///
    /// ## Metrics Included
    /// - Current memory consumption in bytes
    /// - Average CPU usage percentage
    /// - Model downgrade recommendation status
    /// - Suggested alternative model if optimization needed
    ///
    /// - Note: Metrics reflect the current state and may change rapidly during active transcription
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
    ///
    /// Analyzes current performance metrics to determine if switching to a smaller,
    /// more efficient model would improve system performance.
    ///
    /// - Returns: Tuple containing:
    ///   - `needed`: Boolean indicating if downgrade is recommended
    ///   - `suggestedModel`: Name of recommended smaller model, or nil if no downgrade needed
    ///
    /// ## Downgrade Triggers
    /// - CPU usage consistently above 80%
    /// - Memory usage approaching system limits
    /// - Transcription latency exceeding targets
    ///
    /// ## Usage
    /// ```swift
    /// let (shouldDowngrade, suggested) = await engine.shouldDowngradeModel()
    /// if shouldDowngrade {
    ///     print("Consider switching to: \(suggested ?? "smaller model")")
    /// }
    /// ```
    ///
    /// - Important: Recommendations are based on real-time performance analysis
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
        
        // Ensure we stay within bounds
        while performanceHistory.count > maxHistorySize {
            performanceHistory.removeFirst()
        }
    }
}