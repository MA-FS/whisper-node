import SwiftUI

struct PreferencesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Whisper Node")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Blazingly fast, on-device speech-to-text")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Press and hold your hotkey to start recording")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}

#Preview {
    PreferencesView()
}