import SwiftUI
import AppKit

/// Visual recording indicator that displays as a floating orb
///
/// Provides real-time visual feedback for recording states with animations,
/// accessibility support, and theme adaptation.
///
/// ## Features
/// - 80pt diameter floating orb with blur background
/// - State-based color coding (idle, recording, processing, error)
/// - Smooth animations with accessibility considerations
/// - Progress ring for processing state
/// - Theme-aware styling (light/dark/high contrast)
///
/// ## Usage
/// ```swift
/// RecordingIndicatorView(
///     isVisible: $isRecording,
///     state: $recordingState,
///     progress: $processingProgress
/// )
/// ```
public struct RecordingIndicatorView: View {
    @Binding var isVisible: Bool
    @Binding var state: RecordingState
    @Binding var progress: Double
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Angle = .zero
    
    private let orbSize: CGFloat = 80
    private let cornerPadding: CGFloat = 24
    
    // Animation duration constants
    private let recordingPulseDuration: Double = 1.2
    private let processingRotationDuration: Double = 2.0
    private let defaultAnimationDuration: Double = 0.3
    
    // Accessibility constants
    private static let highContrastOpacity: Double = 0.9
    
    public init(
        isVisible: Binding<Bool>,
        state: Binding<RecordingState>,
        progress: Binding<Double>
    ) {
        self._isVisible = isVisible
        self._state = state
        self._progress = progress
    }
    
    public var body: some View {
        GeometryReader { geometry in
            if isVisible {
                ZStack {
                    // Blur background
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .frame(width: orbSize, height: orbSize)
                        .clipShape(Circle())
                    
                    // Main orb content
                    ZStack {
                        // Base circle with state color
                        Circle()
                            .fill(stateColor.opacity(stateOpacity))
                            .frame(width: orbSize, height: orbSize)
                        
                        // Progress ring (only shown during processing)
                        if state == .processing {
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(
                                    stateColor,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                )
                                .frame(width: orbSize - 6, height: orbSize - 6)
                                .rotationEffect(rotationAngle)
                        }
                        
                        // Accessibility icon overlay
                        if differentiateWithoutColor {
                            stateIcon
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }
                    .scaleEffect(pulseScale)
                    .animation(
                        reduceMotion ? .none : pulseAnimation,
                        value: state
                    )
                    .animation(
                        reduceMotion ? .none : pulseAnimation,
                        value: pulseScale
                    )
                }
                .position(
                    x: geometry.size.width - cornerPadding - orbSize / 2,
                    y: geometry.size.height - cornerPadding - orbSize / 2
                )
                .opacity(isVisible ? 1 : 0)
                .animation(
                    .easeInOut(duration: 0.3),
                    value: isVisible
                )
                .onAppear {
                    startAnimations()
                }
                .onDisappear {
                    stopAnimations()
                }
                .onChange(of: state) { newState in
                    updateAnimationsForState(newState)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint)
                .accessibilityValue(accessibilityValue)
                .accessibilityAddTraits(accessibilityTraits)
            }
        }
        .allowsHitTesting(false) // Allow clicks to pass through
        .ignoresSafeArea(.all)
    }
    
    // MARK: - State Colors
    
    private var stateColor: Color {
        switch state {
        case .idle, .recording:
            return .blue
        case .processing:
            return .blue
        case .error:
            return .red
        }
    }
    
    private var stateOpacity: Double {
        let baseOpacity: Double
        switch state {
        case .idle:
            baseOpacity = 0.7
        case .recording, .processing:
            baseOpacity = 0.85
        case .error:
            baseOpacity = 0.7
        }
        
        // High contrast mode support - use 90% opacity as per T19 requirements
        return differentiateWithoutColor ? Self.highContrastOpacity : baseOpacity
    }
    
    // MARK: - Accessibility
    
    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "mic")
        case .recording:
            Image(systemName: "mic.fill")
        case .processing:
            Image(systemName: "waveform")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }
    
    /// Provides a consistent accessibility label for the recording indicator across all states.
    /// 
    /// Returns "Recording indicator" to clearly identify this element's purpose for VoiceOver users.
    /// This label remains constant while the hint and value provide state-specific information.
    private var accessibilityLabel: String {
        return "Recording indicator"
    }
    
    /// Provides concise accessibility hints based on the current recording state.
    /// 
    /// These hints give VoiceOver users immediate context about what the indicator is showing:
    /// - Idle: "Ready to record" 
    /// - Recording: "Recording in progress"
    /// - Processing: "Processing audio"
    /// - Error: "Recording error occurred"
    /// 
    /// Hints are kept short to reduce cognitive load while providing essential context.
    private var accessibilityHint: String {
        switch state {
        case .idle:
            return "Ready to record"
        case .recording:
            return "Recording in progress"
        case .processing:
            return "Processing audio"
        case .error:
            return "Recording error occurred"
        }
    }
    
    /// Provides dynamic accessibility value information for processing state.
    /// 
    /// Returns percentage completion during processing to give VoiceOver users 
    /// real-time feedback on transcription progress. Returns empty string for
    /// other states where progress information isn't applicable.
    private var accessibilityValue: String {
        switch state {
        case .processing:
            let percentage = Int(progress * 100)
            return "\(percentage)% complete"
        default:
            return ""
        }
    }
    
    /// Provides state-appropriate accessibility traits for the recording indicator.
    /// 
    /// Uses `.updatesFrequently` during processing to indicate dynamic content,
    /// and `.playsSound` for other states where audio feedback occurs.
    private var accessibilityTraits: AccessibilityTraits {
        switch state {
        case .processing:
            return .updatesFrequently
        default:
            return .playsSound
        }
    }
    
    // MARK: - Animations
    
    private var pulseAnimation: Animation {
        switch state {
        case .recording:
            return .easeInOut(duration: recordingPulseDuration).repeatForever(autoreverses: true)
        case .processing:
            return .linear(duration: processingRotationDuration).repeatForever(autoreverses: false)
        default:
            return .easeInOut(duration: defaultAnimationDuration)
        }
    }
    
    /// Starts the appropriate animations based on the current recording state.
    private func startAnimations() {
        updateAnimationsForState(state)
    }
    
    /// Resets the pulse scale and rotation angle to their default values, stopping any ongoing animations.
    private func stopAnimations() {
        pulseScale = 1.0
        rotationAngle = .zero
    }
    
    /// Updates animation properties based on the given recording state.
    ///
    /// Adjusts pulsing and rotation values to trigger appropriate animations for idle, recording, processing, or error states. Animations are disabled if reduce motion is enabled.
    private func updateAnimationsForState(_ newState: RecordingState) {
        guard !reduceMotion else {
            pulseScale = 1.0
            rotationAngle = .zero
            return
        }
        
        switch newState {
        case .idle:
            pulseScale = 1.0
            rotationAngle = .zero
            
        case .recording:
            // Start pulsing animation
            withAnimation(pulseAnimation) {
                pulseScale = 1.1
            }
            
        case .processing:
            pulseScale = 1.0
            // Start rotation animation for progress ring
            withAnimation(.linear(duration: processingRotationDuration).repeatForever(autoreverses: false)) {
                rotationAngle = .degrees(360)
            }
            
        case .error:
            pulseScale = 1.0
            rotationAngle = .zero
            // Brief shake animation for error state
            withAnimation(.easeInOut(duration: 0.1).repeatCount(3, autoreverses: true)) {
                pulseScale = 1.05
            }
        }
    }
}

// MARK: - Recording State

/// Represents the current state of the recording system
public enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case error
}

// MARK: - Visual Effect View

/// NSVisualEffectView wrapper for SwiftUI
private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    /// Creates and configures an `NSVisualEffectView` with the specified material and blending mode.
    ///
    /// - Returns: An active `NSVisualEffectView` instance set up for use as a blurred background in SwiftUI.
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    /// Updates the properties of the underlying `NSVisualEffectView` with the specified material and blending mode.
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

// MARK: - Preview

#if DEBUG
struct RecordingIndicatorView_Previews: PreviewProvider {
    @State private static var isVisible = true
    @State private static var state: RecordingState = .recording
    @State private static var progress: Double = 0.6
    
    static var previews: some View {
        Group {
            // Light mode preview
            RecordingIndicatorView(
                isVisible: $isVisible,
                state: $state,
                progress: $progress
            )
            .frame(width: 400, height: 300)
            .preferredColorScheme(.light)
            .previewDisplayName("Light Mode - Recording")
            
            // Dark mode preview
            RecordingIndicatorView(
                isVisible: $isVisible,
                state: $state,
                progress: $progress
            )
            .frame(width: 400, height: 300)
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode - Recording")
            
            // Processing state preview
            RecordingIndicatorView(
                isVisible: $isVisible,
                state: .constant(.processing),
                progress: $progress
            )
            .frame(width: 400, height: 300)
            .previewDisplayName("Processing State")
            
            // Error state preview
            RecordingIndicatorView(
                isVisible: $isVisible,
                state: .constant(.error),
                progress: $progress
            )
            .frame(width: 400, height: 300)
            .previewDisplayName("Error State")
        }
    }
}
#endif