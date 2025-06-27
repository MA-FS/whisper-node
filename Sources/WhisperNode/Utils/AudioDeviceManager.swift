import Foundation
import AVFoundation
import AudioToolbox
import os.log

/// Comprehensive audio device management for WhisperNode
///
/// Provides advanced audio device detection, selection, monitoring, and management
/// capabilities with real-time device change notifications and capability validation.
///
/// ## Features
/// - Real-time audio device enumeration and monitoring
/// - Device capability validation and compatibility checking
/// - Automatic device change detection with notifications
/// - Default device management and fallback handling
/// - Device-specific configuration and optimization
/// - Thread-safe operations with concurrent access protection
///
/// ## Usage
/// ```swift
/// let deviceManager = AudioDeviceManager.shared
/// 
/// // Get available input devices
/// let devices = deviceManager.getAvailableInputDevices()
/// 
/// // Monitor device changes
/// deviceManager.onDeviceListChanged = { devices in
///     // Update UI with new device list
/// }
/// 
/// // Set preferred device
/// try deviceManager.setPreferredInputDevice(deviceID)
/// ```
@MainActor
public class AudioDeviceManager: ObservableObject {
    
    /// Shared singleton instance
    public static let shared = AudioDeviceManager()
    
    /// Logger for audio device operations
    private static let logger = Logger(subsystem: "com.whispernode.audio", category: "AudioDeviceManager")
    
    // MARK: - Types
    
    /// Audio device information structure
    public struct AudioDeviceInfo: Identifiable, Equatable {
        public let id: AudioDeviceID
        public let name: String
        public let manufacturer: String
        public let isDefault: Bool
        public let hasInput: Bool
        public let hasOutput: Bool
        public let sampleRates: [Double]
        public let channelCounts: [UInt32]
        public let isConnected: Bool
        
        public static func == (lhs: AudioDeviceInfo, rhs: AudioDeviceInfo) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    /// Device change notification types
    public enum DeviceChangeType {
        case deviceAdded(AudioDeviceInfo)
        case deviceRemoved(AudioDeviceID)
        case devicePropertiesChanged(AudioDeviceInfo)
        case defaultDeviceChanged(AudioDeviceID?)
    }
    
    /// Device management errors
    public enum DeviceError: Error, LocalizedError {
        case deviceNotFound
        case deviceNotAvailable
        case permissionDenied
        case configurationFailed
        case systemError(OSStatus)
        
        public var errorDescription: String? {
            switch self {
            case .deviceNotFound:
                return "Audio device not found"
            case .deviceNotAvailable:
                return "Audio device not available"
            case .permissionDenied:
                return "Permission denied for audio device access"
            case .configurationFailed:
                return "Failed to configure audio device"
            case .systemError(let status):
                return "System audio error: \(status)"
            }
        }
    }
    
    // MARK: - Properties
    
    /// Current list of available input devices
    @Published public private(set) var availableInputDevices: [AudioDeviceInfo] = []
    
    /// Current default input device
    @Published public private(set) var defaultInputDevice: AudioDeviceInfo?
    
    /// Currently selected preferred device
    @Published public private(set) var preferredInputDevice: AudioDeviceInfo?
    
    /// Device monitoring status
    @Published public private(set) var isMonitoring: Bool = false
    
    // MARK: - Callbacks
    
    /// Called when device list changes
    public var onDeviceListChanged: (([AudioDeviceInfo]) -> Void)?
    
    /// Called when device properties change
    public var onDeviceChanged: ((DeviceChangeType) -> Void)?
    
    /// Called when default device changes
    public var onDefaultDeviceChanged: ((AudioDeviceInfo?) -> Void)?
    
    // MARK: - Private Properties
    
    private nonisolated(unsafe) var deviceListenerProc: AudioObjectPropertyListenerProc?
    private nonisolated(unsafe) var isListenerInstalled = false
    
    // MARK: - Initialization
    
    private init() {
        setupDeviceMonitoring()
        refreshDeviceList()
    }
    
    deinit {
        // Synchronously clean up Core Audio listeners to prevent memory leaks
        if isListenerInstalled {
            removeDeviceListenersSynchronously()
        }
    }
    
    // MARK: - Public Interface
    
    /// Get all available input devices
    /// 
    /// - Returns: Array of audio device information structures
    public func getAvailableInputDevices() -> [AudioDeviceInfo] {
        refreshDeviceList()
        return availableInputDevices
    }
    
    /// Get device information by ID
    /// 
    /// - Parameter deviceID: The audio device ID
    /// - Returns: Device information if found, nil otherwise
    public func getDeviceInfo(for deviceID: AudioDeviceID) -> AudioDeviceInfo? {
        return availableInputDevices.first { $0.id == deviceID }
    }
    
    /// Set preferred input device
    /// 
    /// - Parameter deviceID: Device ID to set as preferred, or nil for default
    /// - Throws: DeviceError if device cannot be set
    public func setPreferredInputDevice(_ deviceID: AudioDeviceID?) throws {
        #if os(macOS)
        if let deviceID = deviceID {
            // Validate device exists and has input capability
            guard let deviceInfo = getDeviceInfo(for: deviceID) else {
                throw DeviceError.deviceNotFound
            }
            
            guard deviceInfo.hasInput else {
                throw DeviceError.deviceNotAvailable
            }
            
            // Set as system default input device
            var device = deviceID
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            let result = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &device
            )
            
            if result != noErr {
                Self.logger.error("Failed to set preferred input device: \(result)")
                throw DeviceError.systemError(result)
            }
            
            preferredInputDevice = deviceInfo
            Self.logger.info("Set preferred input device: \(deviceInfo.name)")
        } else {
            // Reset to system default
            preferredInputDevice = nil
            Self.logger.info("Reset to system default input device")
        }
        #endif
    }
    
    /// Start monitoring device changes
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        #if os(macOS)
        installDeviceListeners()
        #endif
        
        isMonitoring = true
        Self.logger.info("Started audio device monitoring")
    }
    
    /// Stop monitoring device changes
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        #if os(macOS)
        removeDeviceListeners()
        #endif
        
        isMonitoring = false
        Self.logger.info("Stopped audio device monitoring")
    }
    
    /// Validate device compatibility for speech recognition
    /// 
    /// - Parameter deviceID: Device ID to validate
    /// - Returns: True if device is suitable for speech recognition
    public func validateDeviceForSpeechRecognition(_ deviceID: AudioDeviceID) -> Bool {
        guard let deviceInfo = getDeviceInfo(for: deviceID) else { return false }
        
        // Check basic requirements
        guard deviceInfo.hasInput && deviceInfo.isConnected else { return false }
        
        // Check sample rate compatibility (16kHz minimum for speech)
        let hasSuitableSampleRate = deviceInfo.sampleRates.contains { $0 >= 16000 }
        
        // Check channel support (mono minimum)
        let hasMonoSupport = deviceInfo.channelCounts.contains { $0 >= 1 }
        
        return hasSuitableSampleRate && hasMonoSupport
    }
    
    /// Get recommended device for speech recognition
    ///
    /// - Returns: Best available device for speech recognition, or nil if none suitable
    public func getRecommendedSpeechDevice() -> AudioDeviceInfo? {
        let suitableDevices = availableInputDevices.filter { validateDeviceForSpeechRecognition($0.id) }

        // Prefer default device if suitable
        if let defaultDevice = defaultInputDevice,
           validateDeviceForSpeechRecognition(defaultDevice.id) {
            return defaultDevice
        }

        // Otherwise return first suitable device
        return suitableDevices.first
    }

    // MARK: - Private Methods

    /// Setup device monitoring infrastructure with thread safety
    private func setupDeviceMonitoring() {
        #if os(macOS)
        deviceListenerProc = { (objectID, numAddresses, addresses, clientData) in
            guard let clientData = clientData else { return noErr }
            let manager = Unmanaged<AudioDeviceManager>.fromOpaque(clientData).takeUnretainedValue()

            // Use weak reference and safe async dispatch to prevent race conditions
            Task { @MainActor [weak manager] in
                await manager?.handleDeviceListChangeSafely()
            }

            return noErr
        }
        #endif
    }

    /// Install Core Audio device listeners
    private func installDeviceListeners() {
        #if os(macOS)
        guard !isListenerInstalled, let listenerProc = deviceListenerProc else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let clientData = Unmanaged.passUnretained(self).toOpaque()
        let result = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            listenerProc,
            clientData
        )

        if result == noErr {
            isListenerInstalled = true
            Self.logger.debug("Installed device list listener")
        } else {
            Self.logger.error("Failed to install device list listener: \(result)")
        }

        // Also listen for default device changes
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            listenerProc,
            clientData
        )
        #endif
    }

    /// Remove Core Audio device listeners
    private func removeDeviceListeners() {
        #if os(macOS)
        guard isListenerInstalled, let listenerProc = deviceListenerProc else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let clientData = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            listenerProc,
            clientData
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            listenerProc,
            clientData
        )

        isListenerInstalled = false
        Self.logger.debug("Removed device listeners")
        #endif
    }

    /// Remove Core Audio device listeners synchronously (for deinit)
    private nonisolated func removeDeviceListenersSynchronously() {
        #if os(macOS)
        guard isListenerInstalled, let listenerProc = deviceListenerProc else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let clientData = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            listenerProc,
            clientData
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            listenerProc,
            clientData
        )

        isListenerInstalled = false
        #endif
    }

    /// Handle device list changes with thread safety
    private func handleDeviceListChangeSafely() async {
        // Capture current state to prevent race conditions
        let previousDevices = availableInputDevices
        let previousDefaultDevice = defaultInputDevice

        // Refresh device list
        refreshDeviceList()

        // Detect changes and notify
        let currentDevices = availableInputDevices
        let currentDefaultDevice = defaultInputDevice

        // Find added devices
        let addedDevices = currentDevices.filter { current in
            !previousDevices.contains { $0.id == current.id }
        }

        // Find removed devices
        let removedDeviceIDs = previousDevices.compactMap { previous in
            currentDevices.contains { $0.id == previous.id } ? nil : previous.id
        }

        // Notify callbacks safely
        if !addedDevices.isEmpty || !removedDeviceIDs.isEmpty {
            onDeviceListChanged?(currentDevices)

            for device in addedDevices {
                onDeviceChanged?(.deviceAdded(device))
            }

            for deviceID in removedDeviceIDs {
                onDeviceChanged?(.deviceRemoved(deviceID))
            }
        }

        // Check for default device change
        if currentDefaultDevice?.id != previousDefaultDevice?.id {
            onDefaultDeviceChanged?(currentDefaultDevice)
        }
    }

    /// Legacy method for backward compatibility
    private func handleDeviceListChange() {
        Task { @MainActor in
            await handleDeviceListChangeSafely()
        }
    }

    /// Refresh the list of available devices
    private func refreshDeviceList() {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard result == noErr else {
            Self.logger.error("Failed to get device list size: \(result)")
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = Array<AudioDeviceID>(repeating: 0, count: deviceCount)

        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &audioDevices
        )

        guard result == noErr else {
            Self.logger.error("Failed to get device list: \(result)")
            return
        }

        // Filter for input devices and create device info
        let inputDevices = audioDevices.compactMap { deviceID -> AudioDeviceInfo? in
            return createDeviceInfo(for: deviceID)
        }.filter { $0.hasInput }

        availableInputDevices = inputDevices
        defaultInputDevice = getCurrentDefaultInputDevice()

        Self.logger.debug("Refreshed device list: \(inputDevices.count) input devices found")
        #else
        // iOS implementation would go here
        availableInputDevices = []
        defaultInputDevice = nil
        #endif
    }

    /// Get current default input device
    private func getCurrentDefaultInputDevice() -> AudioDeviceInfo? {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard result == noErr && deviceID != kAudioObjectUnknown else {
            return nil
        }

        return createDeviceInfo(for: deviceID)
        #else
        return nil
        #endif
    }

    /// Create device information structure for a device ID
    private func createDeviceInfo(for deviceID: AudioDeviceID) -> AudioDeviceInfo? {
        #if os(macOS)
        // Get device name
        guard let name = getDeviceName(deviceID) else { return nil }

        // Get manufacturer
        let manufacturer = getDeviceManufacturer(deviceID) ?? "Unknown"

        // Check if device has input streams
        let hasInput = deviceHasInputStreams(deviceID)

        // Check if device has output streams
        let hasOutput = deviceHasOutputStreams(deviceID)

        // Get supported sample rates
        let sampleRates = getSupportedSampleRates(deviceID)

        // Get supported channel counts
        let channelCounts = getSupportedChannelCounts(deviceID)

        // Check if device is connected
        let isConnected = isDeviceConnected(deviceID)

        // Check if this is the default device (already queried in refreshDeviceList)
        let isDefault = (defaultInputDevice?.id == deviceID)

        return AudioDeviceInfo(
            id: deviceID,
            name: name,
            manufacturer: manufacturer,
            isDefault: isDefault,
            hasInput: hasInput,
            hasOutput: hasOutput,
            sampleRates: sampleRates,
            channelCounts: channelCounts,
            isConnected: isConnected
        )
        #else
        return nil
        #endif
    }

    /// Get device name with safe buffer handling
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // First, get the actual data size
        var actualSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &actualSize)
        guard result == noErr else {
            Self.logger.error("Failed to get device name size for device \(deviceID): \(result)")
            return "Unknown Device"
        }

        // Validate size is reasonable (prevent buffer overflow attacks)
        guard actualSize > 0 && actualSize <= 512 else {
            Self.logger.error("Invalid device name size \(actualSize) for device \(deviceID)")
            return "Unknown Device"
        }

        // Allocate buffer based on actual size
        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(actualSize))
        defer { nameBuffer.deallocate() }

        // Get the actual data with validated size
        result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &actualSize, nameBuffer)
        guard result == noErr else {
            Self.logger.error("Failed to get device name data for device \(deviceID): \(result)")
            return "Unknown Device"
        }

        // Ensure null termination for safety
        nameBuffer[Int(actualSize) - 1] = 0

        return String(cString: nameBuffer)
        #else
        return nil
        #endif
    }

    /// Get device manufacturer with safe buffer handling
    private func getDeviceManufacturer(_ deviceID: AudioDeviceID) -> String? {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyManufacturer,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // First, get the actual data size
        var actualSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &actualSize)
        guard result == noErr else {
            Self.logger.debug("Failed to get manufacturer size for device \(deviceID): \(result)")
            return "Unknown"
        }

        // Validate size is reasonable (prevent buffer overflow attacks)
        guard actualSize > 0 && actualSize <= 512 else {
            Self.logger.debug("Invalid manufacturer size \(actualSize) for device \(deviceID)")
            return "Unknown"
        }

        // Allocate buffer based on actual size
        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(actualSize))
        defer { nameBuffer.deallocate() }

        // Get the actual data with validated size
        result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &actualSize, nameBuffer)
        guard result == noErr else {
            Self.logger.debug("Failed to get manufacturer data for device \(deviceID): \(result)")
            return "Unknown"
        }

        // Ensure null termination for safety
        nameBuffer[Int(actualSize) - 1] = 0

        return String(cString: nameBuffer)
        #else
        return nil
        #endif
    }

    /// Check if device has input streams
    private func deviceHasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let result = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return result == noErr && dataSize > 0
        #else
        return false
        #endif
    }

    /// Check if device has output streams
    private func deviceHasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let result = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return result == noErr && dataSize > 0
        #else
        return false
        #endif
    }

    /// Get supported sample rates for device
    private func getSupportedSampleRates(_ deviceID: AudioDeviceID) -> [Double] {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard result == noErr else { return [44100.0, 48000.0] } // Default fallback

        let rangeCount = Int(dataSize) / MemoryLayout<AudioValueRange>.size
        var ranges = Array<AudioValueRange>(repeating: AudioValueRange(), count: rangeCount)

        result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &ranges)
        guard result == noErr else { return [44100.0, 48000.0] }

        // Extract sample rates from ranges
        var sampleRates: [Double] = []
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                sampleRates.append(range.mMinimum)
            } else {
                // Add common sample rates within range
                let commonRates = [8000.0, 16000.0, 22050.0, 44100.0, 48000.0, 96000.0, 192000.0]
                for rate in commonRates {
                    if rate >= range.mMinimum && rate <= range.mMaximum {
                        sampleRates.append(rate)
                    }
                }
            }
        }

        return sampleRates.isEmpty ? [44100.0, 48000.0] : Array(Set(sampleRates)).sorted()
        #else
        return [44100.0, 48000.0]
        #endif
    }

    /// Get supported channel counts for device
    private func getSupportedChannelCounts(_ deviceID: AudioDeviceID) -> [UInt32] {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard result == noErr else { return [1, 2] } // Default fallback

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }

        result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferList)
        guard result == noErr else { return [1, 2] }

        var channelCounts: [UInt32] = []
        let bufferCount = Int(bufferList.pointee.mNumberBuffers)

        for i in 0..<bufferCount {
            let buffer = withUnsafePointer(to: bufferList.pointee.mBuffers) { buffersPtr in
                buffersPtr.advanced(by: i).pointee
            }
            channelCounts.append(buffer.mNumberChannels)
        }

        return channelCounts.isEmpty ? [1, 2] : Array(Set(channelCounts)).sorted()
        #else
        return [1, 2]
        #endif
    }

    /// Check if device is currently connected
    private func isDeviceConnected(_ deviceID: AudioDeviceID) -> Bool {
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isAlive: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &isAlive)
        return result == noErr && isAlive != 0
        #else
        return true
        #endif
    }
}
