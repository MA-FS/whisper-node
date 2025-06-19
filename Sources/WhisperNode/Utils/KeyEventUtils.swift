import CoreGraphics
import Foundation

/// Utility functions for analyzing and processing key events and modifier states
///
/// This utility class provides helper functions for the enhanced modifier-only hotkey logic,
/// including release pattern detection, timing validation, and modifier state analysis.
public class KeyEventUtils {
    
    // MARK: - Modifier State Analysis
    
    /// Checks if the current flags represent a release of target modifiers
    ///
    /// Determines whether the current modifier state indicates that one or more
    /// target modifiers have been released compared to the target combination.
    ///
    /// - Parameters:
    ///   - current: Current modifier flags
    ///   - target: Target modifier flags that should be pressed
    /// - Returns: True if any target modifiers have been released
    public static func isReleasingTargetModifiers(current: CGEventFlags, target: CGEventFlags) -> Bool {
        let cleanCurrent = current.cleanedModifierFlags()
        let cleanTarget = target.cleanedModifierFlags()
        
        // Check if we're releasing any of the target modifiers
        let stillPressed = cleanCurrent.intersection(cleanTarget)
        return stillPressed.rawValue < cleanTarget.rawValue
    }
    
    /// Checks if the current flags contain modifiers not in the target combination
    ///
    /// Determines whether additional, unrelated modifiers have been pressed
    /// that are not part of the target hotkey combination.
    ///
    /// - Parameters:
    ///   - current: Current modifier flags
    ///   - target: Target modifier flags for the hotkey
    /// - Returns: True if unrelated modifiers are present
    public static func isAddingUnrelatedModifiers(current: CGEventFlags, target: CGEventFlags) -> Bool {
        let cleanCurrent = current.cleanedModifierFlags()
        let cleanTarget = target.cleanedModifierFlags()
        
        // Check if current flags contain modifiers not in target
        let unrelatedModifiers = cleanCurrent.subtracting(cleanTarget)
        return !unrelatedModifiers.isEmpty
    }
    
    /// Gets the individual modifier flags from a combined flag set
    ///
    /// Breaks down a combined CGEventFlags value into its individual
    /// modifier components for tracking release states.
    ///
    /// - Parameter flags: Combined modifier flags
    /// - Returns: Array of individual modifier flags
    public static func getIndividualModifierFlags(from flags: CGEventFlags) -> [CGEventFlags] {
        var individual: [CGEventFlags] = []
        
        if flags.contains(.maskControl) { individual.append(.maskControl) }
        if flags.contains(.maskAlternate) { individual.append(.maskAlternate) }
        if flags.contains(.maskShift) { individual.append(.maskShift) }
        if flags.contains(.maskCommand) { individual.append(.maskCommand) }
        
        return individual
    }
    
    // MARK: - Release Pattern Detection
    
    /// Analyzes the release pattern to determine if recording should complete
    ///
    /// Evaluates whether all target modifiers have been released within
    /// the acceptable timing tolerance, considering sequential releases.
    ///
    /// - Parameters:
    ///   - current: Current modifier flags
    ///   - target: Target modifier flags
    ///   - releaseState: Dictionary tracking when each modifier was released (using rawValue as key)
    ///   - tolerance: Maximum time difference between releases
    /// - Returns: True if all modifiers released within tolerance
    public static func shouldCompleteRecording(
        current: CGEventFlags,
        target: CGEventFlags,
        releaseState: [UInt64: Date],
        tolerance: TimeInterval
    ) -> Bool {
        let cleanCurrent = current.cleanedModifierFlags()
        let cleanTarget = target.cleanedModifierFlags()

        // If all target modifiers are released, complete immediately
        if cleanCurrent.intersection(cleanTarget).isEmpty {
            return true
        }

        // Check if we have release times for all target modifiers
        let targetModifiers = getIndividualModifierFlags(from: cleanTarget)
        let releasedModifiers = targetModifiers.filter { releaseState[$0.rawValue] != nil }

        // If not all modifiers have been released yet, don't complete
        guard releasedModifiers.count == targetModifiers.count else {
            return false
        }

        // Check if all releases happened within tolerance period
        let releaseTimes = releasedModifiers.compactMap { releaseState[$0.rawValue] }
        guard let earliestRelease = releaseTimes.min(),
              let latestRelease = releaseTimes.max() else {
            return false
        }

        let releaseSpan = latestRelease.timeIntervalSince(earliestRelease)
        return releaseSpan <= tolerance
    }
    
    // MARK: - Timing Validation
    
    /// Validates if a release sequence is within acceptable timing bounds
    ///
    /// Checks whether the time span between the first and last modifier
    /// release is within the configured tolerance period.
    ///
    /// - Parameters:
    ///   - releaseState: Dictionary tracking when each modifier was released (using rawValue as key)
    ///   - tolerance: Maximum acceptable time span
    /// - Returns: True if release sequence is within bounds
    public static func isReleaseSequenceValid(
        releaseState: [UInt64: Date],
        tolerance: TimeInterval
    ) -> Bool {
        guard releaseState.count >= 2 else { return true }

        let releaseTimes = Array(releaseState.values)
        guard let earliest = releaseTimes.min(),
              let latest = releaseTimes.max() else {
            return true
        }

        return latest.timeIntervalSince(earliest) <= tolerance
    }
}

// MARK: - CGEventFlags Extensions

extension CGEventFlags {
    
    /// Gets individual modifier flags as an array
    ///
    /// Convenience property that returns the individual modifier flags
    /// contained in this combined flag set.
    var individualFlags: [CGEventFlags] {
        return KeyEventUtils.getIndividualModifierFlags(from: self)
    }
}
