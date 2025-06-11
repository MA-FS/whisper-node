import Foundation
import CoreGraphics

/// Extension to provide utility methods for CGEventFlags
extension CGEventFlags {
    /// Returns a cleaned version of the flags containing only essential modifier flags
    ///
    /// This method filters out system/internal flags and keeps only the user-relevant
    /// modifier flags: Command, Option/Alt, Shift, and Control.
    ///
    /// - Returns: CGEventFlags containing only essential modifier flags
    var cleanedModifierFlags: CGEventFlags {
        return CGEventFlags(rawValue: self.rawValue & (
            CGEventFlags.maskCommand.rawValue |
            CGEventFlags.maskControl.rawValue |
            CGEventFlags.maskAlternate.rawValue |
            CGEventFlags.maskShift.rawValue
        ))
    }
}