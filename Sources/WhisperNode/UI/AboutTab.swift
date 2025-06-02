import SwiftUI
import Sparkle

struct AboutTab: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    let updater: SPUUpdater?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App Header
            HStack {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .accessibilityLabel("Whisper Node app icon")
                
                VStack(alignment: .leading) {
                    Text("Whisper Node")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Version \(version) (\(build))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Fast, offline speech-to-text for macOS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Update Check Button
                Button("Check for Updates") {
                    updater?.checkForUpdates()
                }
                .buttonStyle(.borderedProminent)
                .disabled(updater?.canCheckForUpdates != true)
                .accessibilityLabel("Check for application updates")
            }
            .padding(.bottom, 10)
            
            Divider()
            
            // Credits Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Credits")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("**Development Team**")
                        .font(.subheadline)
                    Text("Whisper Node is built with passion for developers and power users who value privacy and performance.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("**Open Source Acknowledgments**")
                        .font(.subheadline)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• **whisper.cpp** - Fast C++ implementation of OpenAI's Whisper")
                            .font(.caption)
                        Text("• **Sparkle** - Software update framework for macOS")
                            .font(.caption)
                        Text("• **Swift** - Apple's modern programming language")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // License and Footer
            VStack(spacing: 8) {
                Divider()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Licensed under the MIT License")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("© 2024 Whisper Node. All rights reserved.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Privacy-first • On-device processing • No data collection")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview {
    AboutTab(updater: nil)
        .frame(width: 480, height: 320)
}