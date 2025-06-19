import Foundation
import CoreGraphics
import os.log

/// Dedicated thread for processing CGEventTap events
///
/// This class manages a background thread specifically for event tap processing,
/// isolating keyboard event capture from the main UI thread to improve reliability
/// and responsiveness under high system load.
///
/// ## Key Features
/// - Dedicated background thread for event processing
/// - Proper run loop management and lifecycle control
/// - Thread-safe communication with main thread
/// - Automatic cleanup and error handling
///
/// ## Usage
/// ```swift
/// let eventThread = EventProcessingThread()
/// eventThread.start(with: eventTap)
/// // ... later
/// eventThread.stop()
/// ```
///
/// - Important: Only one EventProcessingThread should be active at a time
/// - Note: Thread lifecycle is managed automatically
public class EventProcessingThread {
    private static let logger = Logger(subsystem: "com.whispernode.threading", category: "event-thread")
    private static let runLoopInterval: TimeInterval = 0.1

    // MARK: - Properties
    private var thread: Thread?
    private var runLoop: RunLoop?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let threadName = "WhisperNode.EventProcessing"
    private var isRunning = false
    private let startupSemaphore = DispatchSemaphore(value: 0)
    
    // MARK: - Thread Lifecycle
    
    /// Start the event processing thread with the given event tap
    ///
    /// Creates and starts a dedicated background thread for event processing.
    /// The thread will have high priority (userInteractive QoS) to ensure
    /// responsive keyboard event handling.
    ///
    /// - Parameter eventTap: The CFMachPort event tap to process
    /// - Returns: True if thread started successfully, false otherwise
    public func start(with eventTap: CFMachPort) -> Bool {
        Self.logger.debug("Starting event processing thread")
        
        guard !isRunning else {
            Self.logger.warning("Event processing thread already running")
            return false
        }
        
        self.eventTap = eventTap
        
        // Create and configure the thread
        thread = Thread { [weak self] in
            self?.runEventLoop()
        }
        
        guard let thread = thread else {
            Self.logger.error("Failed to create event processing thread")
            return false
        }
        
        thread.name = threadName
        thread.qualityOfService = .userInteractive
        thread.start()
        
        // Wait for thread to start up (with timeout)
        let result = startupSemaphore.wait(timeout: .now() + 2.0)
        if result == .timedOut {
            Self.logger.error("Event processing thread startup timed out")
            stop()
            return false
        }
        
        Self.logger.info("Event processing thread started successfully")
        return isRunning
    }
    
    /// Stop the event processing thread
    ///
    /// Cleanly shuts down the background thread and cleans up resources.
    /// Safe to call multiple times or when thread is not running.
    public func stop() {
        Self.logger.debug("Stopping event processing thread")
        
        guard isRunning else {
            Self.logger.debug("Event processing thread not running")
            return
        }
        
        // Cancel the thread and stop the run loop
        thread?.cancel()
        
        if let runLoop = runLoop {
            CFRunLoopStop(runLoop.getCFRunLoop())
        }
        
        // Clean up resources
        cleanup()
        
        Self.logger.info("Event processing thread stopped")
    }
    
    // MARK: - Private Methods
    
    /// Main run loop for the event processing thread
    private func runEventLoop() {
        Self.logger.debug("Event processing thread run loop starting")
        
        // Set up the run loop
        runLoop = RunLoop.current
        
        guard let eventTap = eventTap else {
            Self.logger.error("No event tap provided to event processing thread")
            startupSemaphore.signal()
            return
        }
        
        // Create and add the run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let source = runLoopSource else {
            Self.logger.error("Failed to create run loop source for event processing thread")
            startupSemaphore.signal()
            return
        }
        
        CFRunLoopAddSource(runLoop!.getCFRunLoop(), source, CFRunLoopMode.commonModes)
        
        isRunning = true
        startupSemaphore.signal()
        
        Self.logger.debug("Event processing thread run loop active")
        
        // Keep the run loop alive until cancelled
        while !Thread.current.isCancelled && isRunning {
            _ = autoreleasepool {
                runLoop?.run(mode: .default, before: Date(timeIntervalSinceNow: Self.runLoopInterval))
            }
        }
        
        Self.logger.debug("Event processing thread run loop exiting")
        
        // Cleanup on thread exit
        if let source = runLoopSource, let runLoop = runLoop {
            CFRunLoopRemoveSource(runLoop.getCFRunLoop(), source, CFRunLoopMode.commonModes)
        }
        
        isRunning = false
    }
    
    /// Clean up thread resources
    private func cleanup() {
        isRunning = false
        runLoopSource = nil
        runLoop = nil
        thread = nil
        eventTap = nil
    }
    
    // MARK: - Status
    
    /// Check if the event processing thread is currently running
    public var isThreadRunning: Bool {
        return isRunning && thread?.isExecuting == true
    }
    
    /// Get diagnostic information about the thread
    public func getDiagnostics() -> [String: Any] {
        return [
            "isRunning": isRunning,
            "threadName": threadName,
            "hasThread": thread != nil,
            "hasRunLoop": runLoop != nil,
            "hasEventTap": eventTap != nil,
            "hasRunLoopSource": runLoopSource != nil,
            "threadExecuting": thread?.isExecuting ?? false,
            "threadCancelled": thread?.isCancelled ?? false
        ]
    }
}

/// Thread-safe state management for hotkey processing
///
/// Provides thread-safe access to shared state between the event processing
/// thread and the main thread, using concurrent queues with barrier writes
/// for optimal performance.
///
/// ## Usage
/// ```swift
/// let state = ThreadSafeHotkeyState()
/// state.isRecording = true
/// let recording = state.isRecording
/// ```
///
/// - Important: All property access is thread-safe
/// - Note: Uses concurrent queue with barrier writes for performance
public class ThreadSafeHotkeyState {
    private let queue = DispatchQueue(label: "WhisperNode.HotkeyState", attributes: .concurrent)
    
    // MARK: - Private State
    private var _isRecording = false
    private var _keyDownTime: Date?
    private var _lastEventTime: Date?
    
    // MARK: - Thread-Safe Properties
    
    /// Whether recording is currently active
    public var isRecording: Bool {
        get {
            return queue.sync { _isRecording }
        }
        set {
            queue.sync(flags: .barrier) {
                _isRecording = newValue
            }
        }
    }
    
    /// Time when the hotkey was pressed down
    public var keyDownTime: Date? {
        get {
            return queue.sync { _keyDownTime }
        }
        set {
            queue.sync(flags: .barrier) {
                _keyDownTime = newValue
            }
        }
    }
    
    /// Time of the last processed event
    public var lastEventTime: Date? {
        get {
            return queue.sync { _lastEventTime }
        }
        set {
            queue.sync(flags: .barrier) {
                _lastEventTime = newValue
            }
        }
    }
    
    // MARK: - Utility Methods
    
    /// Reset all state to initial values
    public func reset() {
        queue.async(flags: .barrier) { [weak self] in
            self?._isRecording = false
            self?._keyDownTime = nil
            self?._lastEventTime = nil
        }
    }
    
    /// Get a snapshot of all current state
    public func getSnapshot() -> (isRecording: Bool, keyDownTime: Date?, lastEventTime: Date?) {
        return queue.sync {
            return (_isRecording, _keyDownTime, _lastEventTime)
        }
    }
}
