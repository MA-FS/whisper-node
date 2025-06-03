import SwiftUI

struct GeneralTab: View {
    @StateObject private var settings = SettingsManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        VStack(alignment: .leading, spacing: dynamicSpacing) {
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
        .padding(dynamicPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Dynamic Text Support
    
    private var dynamicSpacing: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium:
            return 20
        case .large, .xLarge:
            return 24
        case .xxLarge, .xxxLarge:
            return 28
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return 32
        @unknown default:
            return 20
        }
    }
    
    private var dynamicPadding: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium:
            return 20
        case .large, .xLarge:
            return 24
        case .xxLarge, .xxxLarge:
            return 28
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return 32
        @unknown default:
            return 20
        }
    }
}

#Preview {
    GeneralTab()
        .frame(width: 480, height: 320)
}