import Foundation
import AVFoundation
import os.log
#if os(macOS)
import AppKit
#endif

/// Enhanced audio permission management for WhisperNode
///
/// Provides comprehensive microphone permission handling with real-time status monitoring,
/// user guidance, and integration with system permission dialogs. Builds upon the existing
/// PermissionHelper to provide audio-specific permission management.
///
/// ## Features
/// - Real-time permission status monitoring with notifications
/// - Enhanced permission request handling with user guidance
/// - Permission status caching and validation
/// - Integration with system permission dialogs
/// - User-friendly error messages and recovery suggestions
/// - Thread-safe operations with concurrent access protection
///
/// ## Usage
/// ```swift
/// let permissionManager = AudioPermissionManager.shared
/// 
/// // Check current status
/// let status = permissionManager.currentPermissionStatus
/// 
/// // Request permission with guidance
/// let granted = await permissionManager.requestPermissionWithGuidance()
/// 
/// // Monitor status changes
/// permissionManager.onPermissionStatusChanged = { status in
///     // Update UI based on permission status
/// }
/// ```
@MainActor
public class AudioPermissionManager: ObservableObject {
    
    /// Shared singleton instance
    public static let shared = AudioPermissionManager()
    
    /// Logger for audio permission operations
    private static let logger = Logger(subsystem: "com.whispernode.audio", category: "AudioPermissionManager")
    
    // MARK: - Types
    
    /// Enhanced permission status with additional context
    public enum PermissionStatus: Equatable {
        case notDetermined
        case granted
        case denied
        case restricted
        case temporarilyUnavailable
        
        /// User-friendly description of the permission status
        public var description: String {
            switch self {
            case .notDetermined:
                return "Permission not yet requested"
            case .granted:
                return "Microphone access granted"
            case .denied:
                return "Microphone access denied"
            case .restricted:
                return "Microphone access restricted by system policy"
            case .temporarilyUnavailable:
                return "Microphone temporarily unavailable"
            }
        }
        
        /// Whether the permission allows audio capture
        public var allowsCapture: Bool {
            return self == .granted
        }
    }
    
    /// Permission request result with additional context
    public struct PermissionResult {
        public let status: PermissionStatus
        public let isNewlyGranted: Bool
        public let userMessage: String?
        public let recoveryAction: (() -> Void)?
        
        public init(status: PermissionStatus, isNewlyGranted: Bool = false, userMessage: String? = nil, recoveryAction: (() -> Void)? = nil) {
            self.status = status
            self.isNewlyGranted = isNewlyGranted
            self.userMessage = userMessage
            self.recoveryAction = recoveryAction
        }
    }
    
    // MARK: - Properties
    
    /// Current permission status
    @Published public private(set) var currentPermissionStatus: PermissionStatus = .notDetermined
    
    /// Whether permission monitoring is active
    @Published public private(set) var isMonitoring: Bool = false
    
    /// Last permission check timestamp
    @Published public private(set) var lastCheckTime: Date?
    
    // MARK: - Callbacks
    
    /// Called when permission status changes
    public var onPermissionStatusChanged: ((PermissionStatus) -> Void)?
    
    /// Called when permission is granted for the first time
    public var onPermissionGranted: (() -> Void)?
    
    /// Called when permission is denied
    public var onPermissionDenied: ((String) -> Void)?
    
    // MARK: - Private Properties
    
    private var monitoringTimer: Timer?
    private var lastKnownStatus: PermissionStatus = .notDetermined
    
    // MARK: - Initialization
    
    private init() {
        updatePermissionStatus()
        startMonitoring()
    }
    
    deinit {
        // Note: Cannot call async methods in deinit
        // Monitoring will be cleaned up automatically
    }
    
    // MARK: - Public Interface
    
    /// Request microphone permission with enhanced user guidance
    /// 
    /// - Returns: Permission result with status and guidance information
    public func requestPermissionWithGuidance() async -> PermissionResult {
        Self.logger.info("Requesting microphone permission with guidance")
        
        let initialStatus = currentPermissionStatus
        
        // If already granted, return immediately
        if initialStatus == .granted {
            return PermissionResult(
                status: .granted,
                isNewlyGranted: false,
                userMessage: "Microphone access is already granted"
            )
        }
        
        // If denied, provide guidance for manual permission change
        if initialStatus == .denied {
            return PermissionResult(
                status: .denied,
                isNewlyGranted: false,
                userMessage: "Microphone access was previously denied. Please enable it in System Preferences > Security & Privacy > Privacy > Microphone.",
                recoveryAction: { [weak self] in
                    self?.openSystemPreferences()
                }
            )
        }
        
        // Request permission
        _ = await requestPermission()
        let newStatus = checkPermissionStatus()
        
        let isNewlyGranted = (initialStatus != .granted && newStatus == .granted)
        
        if isNewlyGranted {
            onPermissionGranted?()
        } else if newStatus == .denied {
            onPermissionDenied?("Microphone permission was denied")
        }
        
        return PermissionResult(
            status: newStatus,
            isNewlyGranted: isNewlyGranted,
            userMessage: getStatusMessage(for: newStatus, wasRequested: true)
        )
    }
    
    /// Request microphone permission (basic)
    /// 
    /// - Returns: True if permission is granted, false otherwise
    public func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            #if os(macOS)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.updatePermissionStatus()
                    continuation.resume(returning: granted)
                }
            }
            #else
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    self?.updatePermissionStatus()
                    continuation.resume(returning: granted)
                }
            }
            #endif
        }
    }
    
    /// Check current permission status without requesting
    /// 
    /// - Returns: Current permission status
    public func checkPermissionStatus() -> PermissionStatus {
        updatePermissionStatus()
        return currentPermissionStatus
    }
    
    /// Validate that microphone is actually accessible
    /// 
    /// - Returns: True if microphone can be accessed for recording
    public func validateMicrophoneAccess() async -> Bool {
        guard currentPermissionStatus == .granted else { return false }
        
        // Try to create a brief audio session to validate actual access
        do {
            #if os(macOS)
            // On macOS, try to access the input node
            let audioEngine = AVAudioEngine()
            let inputNode = audioEngine.inputNode
            let format = inputNode.inputFormat(forBus: 0)
            
            // If we can get the format, microphone is accessible
            return format.sampleRate > 0
            #else
            // On iOS, try to configure audio session
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            try session.setActive(false)
            return true
            #endif
        } catch {
            Self.logger.error("Microphone validation failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Start monitoring permission status changes
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        // Check status immediately
        updatePermissionStatus()
        
        // Set up periodic monitoring (every 2 seconds)
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForStatusChanges()
            }
        }
        
        isMonitoring = true
        Self.logger.info("Started permission status monitoring")
    }
    
    /// Stop monitoring permission status changes
    public func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
        Self.logger.info("Stopped permission status monitoring")
    }
    
    /// Get user-friendly guidance message for current status
    /// 
    /// - Returns: Guidance message for the user
    public func getGuidanceMessage() -> String {
        return getStatusMessage(for: currentPermissionStatus, wasRequested: false)
    }
    
    /// Open system preferences to microphone privacy settings
    public func openSystemPreferences() {
        #if os(macOS)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
        Self.logger.info("Opened system preferences for microphone privacy")
        #endif
    }
    
    // MARK: - Private Methods
    
    /// Update current permission status
    private func updatePermissionStatus() {
        let newStatus = getCurrentSystemPermissionStatus()
        
        if newStatus != currentPermissionStatus {
            let previousStatus = currentPermissionStatus
            currentPermissionStatus = newStatus
            lastCheckTime = Date()
            
            Self.logger.info("Permission status changed: \(previousStatus.description) -> \(newStatus.description)")
            onPermissionStatusChanged?(newStatus)
        }
    }
    
    /// Get current system permission status
    private func getCurrentSystemPermissionStatus() -> PermissionStatus {
        #if os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
        #else
        let status = AVAudioSession.sharedInstance().recordPermission
        switch status {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
        #endif
    }
    
    /// Check for permission status changes
    private func checkForStatusChanges() {
        let currentStatus = getCurrentSystemPermissionStatus()
        if currentStatus != lastKnownStatus {
            lastKnownStatus = currentStatus
            updatePermissionStatus()
        }
    }
    
    /// Get status message for user
    private func getStatusMessage(for status: PermissionStatus, wasRequested: Bool) -> String {
        switch status {
        case .notDetermined:
            return wasRequested ? "Permission request was cancelled" : "Microphone permission is required for voice input"
        case .granted:
            return "Microphone access is enabled and ready"
        case .denied:
            return "Microphone access is disabled. Enable it in System Preferences > Security & Privacy > Privacy > Microphone"
        case .restricted:
            return "Microphone access is restricted by system policy"
        case .temporarilyUnavailable:
            return "Microphone is temporarily unavailable. Please try again"
        }
    }
}
