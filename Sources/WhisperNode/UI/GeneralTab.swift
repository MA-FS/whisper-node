import SwiftUI

struct GeneralTab: View {
    @StateObject private var settings = SettingsManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        VStack(alignment: .leading, spacing: dynamicScaling) {
            // App Icon and Title
            HStack {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .accessibilityLabel("Whisper Node app icon")
                
                VStack(alignment: .leading) {
                    Text("Whisper Node")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 10)
            
            Divider()
            
            // Settings Section
            VStack(alignment: .leading, spacing: 16) {
                Text("General Settings")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                
                // Launch at Login Toggle
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Launch Whisper Node automatically when you log in")
                        .accessibilityHint("When enabled, Whisper Node will start automatically when you log in to your Mac")
                    
                    Text("Automatically start Whisper Node when you log in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Dock Icon Toggle
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Show Whisper Node icon in the Dock")
                        .accessibilityHint("When disabled, Whisper Node will only appear in the menu bar")
                    
                    Text("Show app icon in the Dock (requires restart)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Footer
            HStack {
                Spacer()
                Text("© 2024 Whisper Node. All rights reserved.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(dynamicScaling)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Dynamic Text Support
    
    /// Constants for dynamic spacing based on text size categories
    private enum DynamicSpacing {
        static let standard: CGFloat = 20
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 28
        static let accessibility: CGFloat = 32
    }
    
    /// Calculates responsive spacing and padding values based on the user's dynamic text size preference.
    /// 
    /// This computed property ensures the UI adapts appropriately for users who need larger text sizes,
    /// providing more generous spacing for accessibility text size categories.
    /// 
    /// - Returns: CGFloat value ranging from 20 (standard sizes) to 32 (accessibility sizes)
    /// 
    /// **Size Categories:**
    /// - Standard sizes (xSmall through medium): 20pt spacing
    /// - Large sizes (large through xLarge): 24pt spacing  
    /// - Extra large sizes (xxLarge through xxxLarge): 28pt spacing
    /// - Accessibility sizes (accessibility1 through accessibility5): 32pt spacing
    private var dynamicScaling: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium:
            return DynamicSpacing.standard
        case .large, .xLarge:
            return DynamicSpacing.large
        case .xxLarge, .xxxLarge:
            return DynamicSpacing.extraLarge
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return DynamicSpacing.accessibility
        @unknown default:
            return DynamicSpacing.standard
        }
    }
    
}

#Preview {
    GeneralTab()
        .frame(width: 480, height: 320)
}