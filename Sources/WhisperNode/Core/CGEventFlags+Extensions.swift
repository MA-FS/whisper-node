import CoreGraphics

/// Extensions for CGEventFlags to provide convenient utility methods
extension CGEventFlags {
    
    /// Returns cleaned modifier flags containing only essential modifiers
    ///
    /// Filters the current flags to include only Command, Control, Option/Alt, and Shift
    /// modifiers, removing any system-specific or temporary flags that might interfere
    /// with hotkey matching and comparison operations.
    ///
    /// ## Usage
    /// ```swift
    /// let eventFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskNumericPad]
    /// let cleaned = eventFlags.cleanedModifierFlags
    /// // Result: [.maskControl, .maskAlternate] (NumericPad flag removed)
    /// ```
    ///
    /// - Returns: CGEventFlags containing only Command, Control, Option, and Shift modifiers
    var cleanedModifierFlags: CGEventFlags {
        return CGEventFlags(rawValue: self.rawValue & (
            CGEventFlags.maskCommand.rawValue |
            CGEventFlags.maskControl.rawValue |
            CGEventFlags.maskAlternate.rawValue |
            CGEventFlags.maskShift.rawValue
        ))
    }
}