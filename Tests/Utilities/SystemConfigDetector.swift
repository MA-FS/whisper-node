import Foundation
import AVFoundation
import os.log

/// System Configuration Detector for Integration Testing
///
/// Detects and reports system configuration details to ensure
/// integration tests run appropriately for the current environment.
///
/// ## Features
/// - Hardware architecture detection (Intel vs Apple Silicon)
/// - macOS version identification and compatibility checking
/// - Audio device enumeration and capability detection
/// - System resource availability assessment
/// - Test environment validation
class SystemConfigDetector {
    
    private static let logger = Logger(subsystem: "com.whispernode.tests", category: "config")
    
    // MARK: - System Information
    
    struct SystemInfo {
        let architecture: Architecture
        let osVersion: OperatingSystemVersion
        let isCompatible: Bool
        let audioDevices: [AudioDeviceInfo]
        let memoryInfo: MemoryInfo
        let cpuInfo: CPUInfo
        let testEnvironmentReady: Bool
    }
    
    enum Architecture {
        case intel
        case appleSilicon
        case unknown
        
        var description: String {
            switch self {
            case .intel: return "Intel x86_64"
            case .appleSilicon: return "Apple Silicon ARM64"
            case .unknown: return "Unknown"
            }
        }
    }
    
    struct AudioDeviceInfo {
        let name: String
        let deviceID: AudioDeviceID
        let isInput: Bool
        let isOutput: Bool
        let sampleRates: [Double]
        let channels: Int
    }
    
    struct MemoryInfo {
        let totalMemory: UInt64  // in bytes
        let availableMemory: UInt64
        let memoryPressure: MemoryPressure
    }
    
    enum MemoryPressure {
        case normal
        case warning
        case critical
    }
    
    struct CPUInfo {
        let coreCount: Int
        let logicalCoreCount: Int
        let currentLoad: Double
        let architecture: String
    }
    
    // MARK: - Detection Methods
    
    static func detectSystemConfiguration() -> SystemInfo {
        logger.info("Detecting system configuration for integration tests")
        
        let architecture = detectArchitecture()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let isCompatible = checkCompatibility(osVersion: osVersion, architecture: architecture)
        let audioDevices = detectAudioDevices()
        let memoryInfo = detectMemoryInfo()
        let cpuInfo = detectCPUInfo()
        let testEnvironmentReady = validateTestEnvironment()
        
        let systemInfo = SystemInfo(
            architecture: architecture,
            osVersion: osVersion,
            isCompatible: isCompatible,
            audioDevices: audioDevices,
            memoryInfo: memoryInfo,
            cpuInfo: cpuInfo,
            testEnvironmentReady: testEnvironmentReady
        )
        
        logSystemInfo(systemInfo)
        return systemInfo
    }
    
    static func detectArchitecture() -> Architecture {
        var systemInfo = utsname()
        uname(&systemInfo)
        
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        
        guard let machineString = machine else {
            return .unknown
        }
        
        if machineString.hasPrefix("arm64") {
            return .appleSilicon
        } else if machineString.hasPrefix("x86_64") {
            return .intel
        } else {
            return .unknown
        }
    }
    
    static func checkCompatibility(osVersion: OperatingSystemVersion, architecture: Architecture) -> Bool {
        // Check minimum macOS version (10.15+)
        let minimumVersion = OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0)
        let isVersionCompatible = ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumVersion)
        
        // Check architecture compatibility
        let isArchitectureSupported = architecture != .unknown
        
        return isVersionCompatible && isArchitectureSupported
    }
    
    static func detectAudioDevices() -> [AudioDeviceInfo] {
        var devices: [AudioDeviceInfo] = []
        
        // Get audio device count
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            logger.warning("Failed to get audio device count")
            return devices
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array<AudioDeviceID>(repeating: 0, count: deviceCount)
        
        let getDevicesStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard getDevicesStatus == noErr else {
            logger.warning("Failed to get audio device IDs")
            return devices
        }
        
        // Get device information
        for deviceID in deviceIDs {
            if let deviceInfo = getAudioDeviceInfo(deviceID: deviceID) {
                devices.append(deviceInfo)
            }
        }
        
        return devices
    }
    
    static func detectMemoryInfo() -> MemoryInfo {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        
        // Get available memory (simplified)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        let availableMemory = kerr == KERN_SUCCESS ? totalMemory - UInt64(info.resident_size) : totalMemory / 2
        
        // Determine memory pressure (simplified)
        let usageRatio = Double(totalMemory - availableMemory) / Double(totalMemory)
        let memoryPressure: MemoryPressure
        if usageRatio > 0.9 {
            memoryPressure = .critical
        } else if usageRatio > 0.7 {
            memoryPressure = .warning
        } else {
            memoryPressure = .normal
        }
        
        return MemoryInfo(
            totalMemory: totalMemory,
            availableMemory: availableMemory,
            memoryPressure: memoryPressure
        )
    }
    
    static func detectCPUInfo() -> CPUInfo {
        let coreCount = ProcessInfo.processInfo.processorCount
        let logicalCoreCount = ProcessInfo.processInfo.activeProcessorCount
        
        // Get current CPU load (simplified)
        let currentLoad = getCurrentCPULoad()
        
        // Get architecture string
        let architecture = detectArchitecture().description
        
        return CPUInfo(
            coreCount: coreCount,
            logicalCoreCount: logicalCoreCount,
            currentLoad: currentLoad,
            architecture: architecture
        )
    }
    
    static func validateTestEnvironment() -> Bool {
        // Check accessibility permissions
        let hasAccessibilityPermissions = AXIsProcessTrusted()
        
        // Check if running in test environment
        let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        
        return hasAccessibilityPermissions || isTestEnvironment
    }
    
    // MARK: - Helper Methods
    
    private static func getAudioDeviceInfo(deviceID: AudioDeviceID) -> AudioDeviceInfo? {
        // Get device name
        guard let name = getAudioDeviceName(deviceID: deviceID) else {
            return nil
        }
        
        // Check input/output capabilities
        let isInput = hasAudioStreams(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
        let isOutput = hasAudioStreams(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
        
        // Get sample rates (simplified)
        let sampleRates = [44100.0, 48000.0, 96000.0] // Common rates
        
        // Get channel count (simplified)
        let channels = 2 // Assume stereo
        
        return AudioDeviceInfo(
            name: name,
            deviceID: deviceID,
            isInput: isInput,
            isOutput: isOutput,
            sampleRates: sampleRates,
            channels: channels
        )
    }
    
    private static func getAudioDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return nil }
        
        var name: CFString?
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        guard status == noErr, let deviceName = name else { return nil }
        
        return deviceName as String
    }
    
    private static func hasAudioStreams(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }
    
    private static func getCurrentCPULoad() -> Double {
        // Simplified CPU load detection
        return 0.1 // Return 10% as placeholder
    }
    
    private static func logSystemInfo(_ info: SystemInfo) {
        logger.info("System Configuration:")
        logger.info("  Architecture: \(info.architecture.description)")
        logger.info("  macOS Version: \(info.osVersion.majorVersion).\(info.osVersion.minorVersion).\(info.osVersion.patchVersion)")
        logger.info("  Compatible: \(info.isCompatible)")
        logger.info("  Audio Devices: \(info.audioDevices.count)")
        logger.info("  Memory: \(info.memoryInfo.totalMemory / 1024 / 1024 / 1024) GB total")
        logger.info("  CPU Cores: \(info.cpuInfo.coreCount)")
        logger.info("  Test Environment Ready: \(info.testEnvironmentReady)")
    }
}
