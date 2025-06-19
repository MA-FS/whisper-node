import Foundation
import os.log

/// Centralized thread management utilities for WhisperNode
///
/// Provides thread safety helpers, synchronization primitives, and performance
/// monitoring for multi-threaded operations in the WhisperNode application.
///
/// ## Key Features
/// - Thread-safe execution utilities
/// - Performance monitoring and diagnostics
/// - Synchronization helpers
/// - Thread lifecycle management
///
/// ## Usage
/// ```swift
/// ThreadManager.shared.executeOnMainThread {
///     // UI updates
/// }
/// 
/// let result = ThreadManager.shared.executeWithTimeout(timeout: 5.0) {
///     // Long-running operation
/// }
/// ```
///
/// - Important: Use for coordinating multi-threaded operations
/// - Note: Singleton pattern for centralized thread management
public class ThreadManager {
    public static let shared = ThreadManager()
    private static let logger = Logger(subsystem: "com.whispernode.threading", category: "thread-manager")
    
    private init() {}
    
    // MARK: - Main Thread Utilities
    
    /// Execute a block on the main thread
    ///
    /// Ensures the given block executes on the main thread, either immediately
    /// if already on main thread, or asynchronously if on a background thread.
    ///
    /// - Parameter block: The block to execute on main thread
    public func executeOnMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
    }
    
    /// Execute a block on the main thread and wait for completion
    ///
    /// Synchronously executes the given block on the main thread.
    /// Use with caution to avoid deadlocks.
    ///
    /// - Parameter block: The block to execute on main thread
    /// - Warning: Can cause deadlocks if called from main thread
    public func executeOnMainThreadSync<T>(_ block: @escaping () -> T) -> T {
        if Thread.isMainThread {
            return block()
        } else {
            return DispatchQueue.main.sync {
                return block()
            }
        }
    }
    
    // MARK: - Background Thread Utilities
    
    /// Execute a block on a background thread with specified quality of service
    ///
    /// - Parameters:
    ///   - qos: Quality of service for the background thread
    ///   - block: The block to execute
    public func executeOnBackground(qos: DispatchQoS.QoSClass = .default, _ block: @escaping () -> Void) {
        DispatchQueue.global(qos: qos).async {
            block()
        }
    }
    
    /// Execute a block with a timeout
    ///
    /// Executes the given block on a background thread with a specified timeout.
    /// Returns nil if the operation times out.
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait for completion
    ///   - block: The block to execute
    /// - Returns: Result of the block or nil if timeout occurred
    public func executeWithTimeout<T>(timeout: TimeInterval, _ block: @escaping () -> T) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        
        DispatchQueue.global().async {
            result = block()
            semaphore.signal()
        }
        
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        return waitResult == .success ? result : nil
    }
    
    // MARK: - Thread Safety Utilities
    
    /// Create a thread-safe wrapper for a value
    ///
    /// Returns a thread-safe accessor for reading and writing values
    /// using a concurrent queue with barrier writes.
    ///
    /// - Parameter initialValue: The initial value to wrap
    /// - Returns: Thread-safe value accessor
    public func createThreadSafeValue<T>(_ initialValue: T) -> ThreadSafeValue<T> {
        return ThreadSafeValue(initialValue)
    }
    
    /// Create a serial queue for synchronized access
    ///
    /// - Parameter label: Label for the queue
    /// - Returns: Serial dispatch queue
    public func createSerialQueue(label: String) -> DispatchQueue {
        return DispatchQueue(label: "WhisperNode.\(label)")
    }
    
    /// Create a concurrent queue for parallel access
    ///
    /// - Parameter label: Label for the queue
    /// - Returns: Concurrent dispatch queue
    public func createConcurrentQueue(label: String) -> DispatchQueue {
        return DispatchQueue(label: "WhisperNode.\(label)", attributes: .concurrent)
    }
    
    // MARK: - Performance Monitoring
    
    /// Measure execution time of a block
    ///
    /// - Parameters:
    ///   - label: Label for logging
    ///   - block: Block to measure
    /// - Returns: Tuple of result and execution time
    public func measureExecutionTime<T>(label: String, _ block: () throws -> T) rethrows -> (result: T, duration: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        if duration > 0.001 { // Log if execution takes more than 1ms
            Self.logger.debug("[\(label)] Execution time: \(duration * 1000)ms")
        }
        
        return (result, duration)
    }
    
    /// Get current thread information
    ///
    /// - Returns: Dictionary with thread information
    public func getCurrentThreadInfo() -> [String: Any] {
        let thread = Thread.current
        return [
            "isMainThread": thread.isMainThread,
            "threadName": thread.name ?? "unnamed",
            "qualityOfService": thread.qualityOfService.rawValue,
            "threadPriority": thread.threadPriority,
            "isExecuting": thread.isExecuting,
            "isCancelled": thread.isCancelled,
            "isFinished": thread.isFinished
        ]
    }
    
    /// Get system thread information
    ///
    /// - Returns: Dictionary with system thread information
    public func getSystemThreadInfo() -> [String: Any] {
        return [
            "activeProcessorCount": ProcessInfo.processInfo.activeProcessorCount,
            "processorCount": ProcessInfo.processInfo.processorCount,
            "physicalMemory": ProcessInfo.processInfo.physicalMemory,
            "systemUptime": ProcessInfo.processInfo.systemUptime
        ]
    }
}

/// Thread-safe value wrapper
///
/// Provides thread-safe access to a value using a concurrent queue
/// with barrier writes for optimal read performance.
///
/// ## Usage
/// ```swift
/// let safeValue = ThreadSafeValue(42)
/// safeValue.value = 100
/// let current = safeValue.value
/// ```
public class ThreadSafeValue<T> {
    private let queue: DispatchQueue
    private var _value: T
    
    /// Initialize with an initial value
    ///
    /// - Parameter initialValue: The initial value
    public init(_ initialValue: T) {
        self._value = initialValue
        self.queue = DispatchQueue(label: "ThreadSafeValue", attributes: .concurrent)
    }
    
    /// Thread-safe value accessor
    public var value: T {
        get {
            return queue.sync { _value }
        }
        set {
            queue.async(flags: .barrier) { [weak self] in
                self?._value = newValue
            }
        }
    }
    
    /// Atomically update the value
    ///
    /// - Parameter transform: Function to transform the current value
    /// - Returns: The new value
    @discardableResult
    public func update(_ transform: @escaping (T) -> T) -> T {
        return queue.sync(flags: .barrier) {
            _value = transform(_value)
            return _value
        }
    }
    
    /// Atomically read and update the value
    ///
    /// - Parameter transform: Function that receives current value and returns new value
    /// - Returns: Tuple of old and new values
    public func readAndUpdate(_ transform: @escaping (T) -> T) -> (oldValue: T, newValue: T) {
        return queue.sync(flags: .barrier) {
            let oldValue = _value
            _value = transform(_value)
            return (oldValue, _value)
        }
    }
}

/// Thread synchronization utilities
public extension ThreadManager {
    
    /// Create a counting semaphore
    ///
    /// - Parameter value: Initial semaphore value
    /// - Returns: Dispatch semaphore
    func createSemaphore(value: Int = 0) -> DispatchSemaphore {
        return DispatchSemaphore(value: value)
    }
    
    /// Create a dispatch group for coordinating multiple operations
    ///
    /// - Returns: Dispatch group
    func createDispatchGroup() -> DispatchGroup {
        return DispatchGroup()
    }
    
    /// Wait for multiple operations to complete
    ///
    /// - Parameters:
    ///   - group: Dispatch group to wait for
    ///   - timeout: Maximum time to wait
    /// - Returns: True if all operations completed, false if timeout
    func waitForGroup(_ group: DispatchGroup, timeout: TimeInterval) -> Bool {
        let result = group.wait(timeout: .now() + timeout)
        return result == .success
    }
}

/// Thread debugging utilities
public extension ThreadManager {
    
    /// Log current thread information
    ///
    /// - Parameter context: Context string for logging
    func logCurrentThread(context: String = "") {
        let info = getCurrentThreadInfo()
        let prefix = context.isEmpty ? "" : "[\(context)] "
        
        Self.logger.debug("\(prefix)Thread Info:")
        Self.logger.debug("  Main Thread: \(info["isMainThread"] as? Bool ?? false)")
        Self.logger.debug("  Name: \(info["threadName"] as? String ?? "unknown")")
        Self.logger.debug("  QoS: \(info["qualityOfService"] as? Int ?? 0)")
        Self.logger.debug("  Priority: \(info["threadPriority"] as? Double ?? 0.0)")
    }
    
    /// Validate thread expectations
    ///
    /// - Parameters:
    ///   - expectedMainThread: Whether operation should be on main thread
    ///   - context: Context for error reporting
    /// - Returns: True if thread expectations are met
    func validateThread(expectedMainThread: Bool, context: String = "") -> Bool {
        let isMainThread = Thread.isMainThread
        let isValid = isMainThread == expectedMainThread
        
        if !isValid {
            let expected = expectedMainThread ? "main" : "background"
            let actual = isMainThread ? "main" : "background"
            Self.logger.warning("[\(context)] Thread validation failed: expected \(expected), got \(actual)")
        }
        
        return isValid
    }
}
