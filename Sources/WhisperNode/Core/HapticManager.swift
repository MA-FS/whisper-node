import Foundation
import CoreHaptics
import AppKit

/// Manages haptic feedback for recording events on supported MacBooks.
/// Provides subtle feedback for recording start/stop events while respecting accessibility preferences.
@MainActor
public class HapticManager: ObservableObject {
    
    // MARK: - Public Properties
    
    /// Shared instance for global access
    public static let shared = HapticManager()
    
    /// Whether haptic feedback is enabled in preferences
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "hapticFeedbackEnabled")
            if !isEnabled {
                stopEngine()
            } else {
                setupEngine()
            }
        }
    }
    
    /// Current haptic intensity (0.1 to 1.0)
    @Published public var intensity: Double {
        didSet {
            intensity = max(0.1, min(1.0, intensity))
            UserDefaults.standard.set(intensity, forKey: "hapticIntensity")
            // Clear cached patterns when intensity changes
            cachedPatterns.removeAll()
        }
    }
    
    // MARK: - Private Properties
    
    private var hapticEngine: CHHapticEngine?
    private var isEngineStarted = false
    private var cachedPatterns: [String: CHHapticPattern] = [:]
    
    // MARK: - Constants
    
    private static let engineStartupDelay: UInt64 = 10_000_000 // 10ms
    private static let engineResetDelay: UInt64 = 100_000_000 // 100ms
    
    // MARK: - Initialization
    
    private init() {
        // Load preferences
        self.isEnabled = UserDefaults.standard.object(forKey: "hapticFeedbackEnabled") as? Bool ?? true
        self.intensity = UserDefaults.standard.object(forKey: "hapticIntensity") as? Double ?? 0.3
        
        setupEngine()
    }
    
    // MARK: - Public Methods
    
    /// Triggers haptic feedback for recording start
    public func recordingStarted() {
        guard isEnabled && shouldProvideHapticFeedback() else { return }
        Task {
            await playLightTap()
        }
    }
    
    /// Triggers haptic feedback for recording stop
    public func recordingStopped() {
        guard isEnabled && shouldProvideHapticFeedback() else { return }
        Task {
            await playLightTap()
        }
    }
    
    /// Triggers haptic feedback for recording cancellation (lighter feedback)
    public func recordingCancelled() {
        guard isEnabled && shouldProvideHapticFeedback() else { return }
        Task {
            await playCancelTap()
        }
    }
    
    /// Triggers haptic feedback for error states
    public func errorOccurred() {
        guard isEnabled && shouldProvideHapticFeedback() else { return }
        Task {
            await playDoubleTap()
        }
    }
    
    /// Triggers haptic feedback for successful text insertion
    public func textInserted() {
        guard isEnabled && shouldProvideHapticFeedback() else { return }
        Task {
            await playSuccessTap()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupEngine() {
        guard isEnabled else { return }
        
        // Check if device supports haptics
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }
        
        do {
            hapticEngine = try CHHapticEngine()
            
            // Set up engine state change handler
            hapticEngine?.stoppedHandler = { [weak self] reason in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isEngineStarted = false
                    switch reason {
                    case .audioSessionInterrupt:
                        // Will restart when session becomes active again
                        break
                    case .applicationSuspended:
                        // Will restart when app becomes active
                        break
                    case .idleTimeout:
                        // Auto restart for idle timeout
                        break
                    case .engineDestroyed:
                        // Engine was destroyed, need to recreate
                        break
                    case .gameControllerDisconnect:
                        // Game controller disconnected, ignore for our use case
                        break
                    case .systemError:
                        // Log error but don't crash
                        break
                    case .notifyWhenFinished:
                        // Expected stop
                        break
                    @unknown default:
                        // Handle future cases
                        break
                    }
                }
            }
            
            hapticEngine?.resetHandler = { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isEngineStarted = false
                    self.stopEngine()
                    try? await Task.sleep(nanoseconds: Self.engineResetDelay)
                    self.setupEngine()
                }
            }
            
            startEngine()
            
        } catch {
            // Haptics not available - fail gracefully
            hapticEngine = nil
        }
    }
    
    private func startEngine() {
        guard let engine = hapticEngine, !isEngineStarted else { return }
        
        do {
            try engine.start()
            isEngineStarted = true
        } catch {
            // Engine failed to start - fail gracefully
            isEngineStarted = false
        }
    }
    
    private func stopEngine() {
        guard let engine = hapticEngine else { return }
        engine.stop()
        isEngineStarted = false
    }
    
    private func shouldProvideHapticFeedback() -> Bool {
        // Respect accessibility preferences
        if #available(macOS 12.0, *) {
            return !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        return true
    }
    
    private func playLightTap() async {
        await playHapticPattern([
            createHapticEvent(intensity: intensity, sharpness: 0.5, delay: 0.0)
        ], cacheKey: "lightTap")
    }
    
    private func playDoubleTap() async {
        await playHapticPattern([
            createHapticEvent(intensity: intensity * 0.8, sharpness: 0.7, delay: 0.0),
            createHapticEvent(intensity: intensity * 0.8, sharpness: 0.7, delay: 0.1)
        ], cacheKey: "doubleTap")
    }
    
    private func playSuccessTap() async {
        await playHapticPattern([
            createHapticEvent(intensity: intensity * 0.6, sharpness: 0.3, delay: 0.0)
        ], cacheKey: "successTap")
    }
    
    private func playCancelTap() async {
        await playHapticPattern([
            createHapticEvent(intensity: intensity * 0.4, sharpness: 0.2, delay: 0.0)
        ], cacheKey: "cancelTap")
    }
    
    private func createHapticEvent(intensity: Double, sharpness: Double, delay: TimeInterval) -> CHHapticEvent {
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity))
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))
        
        return CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensityParam, sharpnessParam],
            relativeTime: delay
        )
    }
    
    private func getOrCreatePattern(for events: [CHHapticEvent], key: String) throws -> CHHapticPattern {
        if let cached = cachedPatterns[key] {
            return cached
        }
        let pattern = try CHHapticPattern(events: events, parameters: [])
        cachedPatterns[key] = pattern
        return pattern
    }
    
    private func playHapticPattern(_ events: [CHHapticEvent], cacheKey: String) async {
        guard let engine = hapticEngine else { return }
        
        // Ensure engine is started
        if !isEngineStarted {
            startEngine()
            // Give engine time to start
            try? await Task.sleep(nanoseconds: Self.engineStartupDelay)
        }
        
        guard isEngineStarted else { return }
        
        do {
            let pattern = try getOrCreatePattern(for: events, key: cacheKey)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // Haptic playback failed - fail gracefully
        }
    }
}

// MARK: - Extensions

extension HapticManager {
    
    /// Convenience method to test haptic feedback
    public func testHaptic() {
        guard isEnabled else { return }
        Task {
            await playLightTap()
        }
    }
    
    /// Reset to default settings
    public func resetToDefaults() {
        isEnabled = true
        intensity = 0.3
    }
}