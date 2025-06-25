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
    @State private var glowOpacity: Double = 0.0
    @State private var shadowRadius: CGFloat = 0
    @State private var breathingScale: CGFloat = 1.0
    @State private var particleOpacity: Double = 0.0
    @State private var stateTransitionProgress: Double = 0.0

    private let orbSize: CGFloat = 80
    private let cornerPadding: CGFloat = 24

    // Enhanced animation duration constants for Siri-like experience
    private let recordingPulseDuration: Double = 1.8  // Slower, more natural breathing
    private let processingRotationDuration: Double = 2.5  // Smoother rotation
    private let defaultAnimationDuration: Double = 0.4  // Slightly longer for smoothness
    private let completionPulseDuration: Double = 0.3  // More pronounced success
    private let completionReturnDuration: Double = 0.4
    private let stateTransitionDuration: Double = 0.6  // Smooth state transitions
    private let glowAnimationDuration: Double = 0.8
    private let breathingDuration: Double = 2.2  // Natural breathing rhythm
    
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
                mainOrbView
                    .position(
                        x: geometry.size.width - orbSize / 2 - cornerPadding,
                        y: geometry.size.height - orbSize / 2 - cornerPadding
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(accessibilityTraits)
        .onChange(of: state) { newState in
            updateAnimationsForState(newState)
        }
        .onAppear {
            startAnimations()
        }
        .onDisappear {
            stopAnimations()
        }
    }

    private var mainOrbView: some View {
        ZStack {
            // Blur background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .frame(width: orbSize, height: orbSize)
                .clipShape(Circle())

            // Enhanced main orb content
            orbContentView
                .scaleEffect(pulseScale)
                .animation(
                    reduceMotion ? .none : enhancedStateAnimation,
                    value: state
                )
                .animation(
                    reduceMotion ? .none : enhancedPulseAnimation,
                    value: pulseScale
                )
        }
    }

    private var orbContentView: some View {
        ZStack {
            // Outer glow effect for active states
            if glowOpacity > 0 {
                Circle()
                    .fill(stateColor.opacity(glowOpacity * 0.3))
                    .frame(width: orbSize + 20, height: orbSize + 20)
                    .blur(radius: 8)
                    .scaleEffect(breathingScale)
            }

            // Shadow layer for depth
            Circle()
                .fill(Color.black.opacity(0.15))
                .frame(width: orbSize, height: orbSize)
                .blur(radius: shadowRadius)
                .offset(y: shadowRadius / 2)

            // Base circle with enhanced state color
            baseCircleView

            // Inner highlight for glass effect
            highlightView

            // Enhanced progress ring
            if state == .processing {
                progressRingView
            }

            // Completion particles effect
            if state == .completed && particleOpacity > 0 {
                particlesView
            }

            // Accessibility icon overlay
            if differentiateWithoutColor {
                accessibilityIconView
            }
        }
    }

    private var baseCircleView: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        stateColor.opacity(stateOpacity * 1.1),
                        stateColor.opacity(stateOpacity * 0.8)
                    ]),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: orbSize / 2
                )
            )
            .frame(width: orbSize, height: orbSize)
    }

    private var highlightView: some View {
        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.3),
                        Color.clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: orbSize * 0.6, height: orbSize * 0.6)
            .offset(x: -orbSize * 0.1, y: -orbSize * 0.1)
    }

    private var progressRingView: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        stateColor,
                        stateColor.opacity(0.6),
                        stateColor
                    ]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
            .frame(width: orbSize - 8, height: orbSize - 8)
            .rotationEffect(rotationAngle)
    }

    private var particlesView: some View {
        ForEach(0..<8, id: \.self) { index in
            Circle()
                .fill(Color.green.opacity(particleOpacity))
                .frame(width: 4, height: 4)
                .offset(
                    x: cos(Double(index) * .pi / 4) * (Double(orbSize) / 2 + 15),
                    y: sin(Double(index) * .pi / 4) * (Double(orbSize) / 2 + 15)
                )
                .scaleEffect(particleOpacity)
        }
    }

    private var accessibilityIconView: some View {
        stateIcon
            .font(.system(size: 24, weight: .medium))
            .foregroundColor(.primary)
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - State Colors
    
    private var stateColor: Color {
        switch state {
        case .idle, .recording:
            return .blue
        case .processing:
            return .blue
        case .completed:
            return .green
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
        case .completed:
            baseOpacity = 0.8
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
        case .completed:
            Image(systemName: "checkmark.circle.fill")
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
        case .completed:
            return "Text insertion completed"
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
    
    // MARK: - Enhanced Animations for Siri-like Experience

    private var enhancedStateAnimation: Animation {
        .spring(response: stateTransitionDuration, dampingFraction: 0.8, blendDuration: 0.2)
    }

    private var enhancedPulseAnimation: Animation {
        switch state {
        case .recording:
            return .easeInOut(duration: recordingPulseDuration).repeatForever(autoreverses: true)
        case .processing:
            return .linear(duration: processingRotationDuration).repeatForever(autoreverses: false)
        case .completed:
            return .spring(response: completionPulseDuration, dampingFraction: 0.6, blendDuration: 0.1)
        default:
            return .spring(response: defaultAnimationDuration, dampingFraction: 0.8, blendDuration: 0.1)
        }
    }

    private var breathingAnimation: Animation {
        .easeInOut(duration: breathingDuration).repeatForever(autoreverses: true)
    }

    // Legacy animation for backward compatibility
    private var pulseAnimation: Animation {
        enhancedPulseAnimation
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
    
    /// Enhanced animation state management for Siri-like visual feedback
    ///
    /// Provides smooth, polished transitions between states with sophisticated visual effects
    /// including glow, shadow, breathing, and particle animations. Respects accessibility preferences.
    private func updateAnimationsForState(_ newState: RecordingState) {
        guard !reduceMotion else {
            resetAllAnimations()
            return
        }

        // Smooth state transition with anticipation
        withAnimation(enhancedStateAnimation) {
            stateTransitionProgress = 1.0
        }

        switch newState {
        case .idle:
            animateToIdleState()

        case .recording:
            animateToRecordingState()

        case .processing:
            animateToProcessingState()

        case .completed:
            animateToCompletedState()

        case .error:
            animateToErrorState()
        }
    }

    private func resetAllAnimations() {
        pulseScale = 1.0
        rotationAngle = .zero
        glowOpacity = 0.0
        shadowRadius = 0
        breathingScale = 1.0
        particleOpacity = 0.0
        stateTransitionProgress = 0.0
    }

    private func animateToIdleState() {
        withAnimation(enhancedStateAnimation) {
            pulseScale = 1.0
            rotationAngle = .zero
            glowOpacity = 0.0
            shadowRadius = 2
            breathingScale = 1.0
            particleOpacity = 0.0
        }
    }

    private func animateToRecordingState() {
        // Gentle breathing animation with subtle glow
        withAnimation(enhancedPulseAnimation) {
            pulseScale = 1.08
        }

        withAnimation(.easeInOut(duration: glowAnimationDuration)) {
            glowOpacity = 0.6
            shadowRadius = 8
        }

        // Start breathing animation
        withAnimation(breathingAnimation) {
            breathingScale = 1.05
        }
    }

    private func animateToProcessingState() {
        withAnimation(enhancedStateAnimation) {
            pulseScale = 1.0
            glowOpacity = 0.8
            shadowRadius = 12
            breathingScale = 1.0
        }

        // Smooth rotation animation for progress ring
        withAnimation(.linear(duration: processingRotationDuration).repeatForever(autoreverses: false)) {
            rotationAngle = .degrees(360)
        }
    }

    private func animateToCompletedState() {
        // Success pulse with particle burst
        withAnimation(.spring(response: completionPulseDuration, dampingFraction: 0.5)) {
            pulseScale = 1.2
            glowOpacity = 1.0
            shadowRadius = 15
            particleOpacity = 1.0
        }

        // Particle fade and return to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + completionPulseDuration) {
            withAnimation(.easeOut(duration: completionReturnDuration)) {
                self.pulseScale = 1.0
                self.glowOpacity = 0.0
                self.shadowRadius = 2
                self.particleOpacity = 0.0
            }
        }

        // Reset rotation
        withAnimation(enhancedStateAnimation) {
            rotationAngle = .zero
        }
    }

    private func animateToErrorState() {
        // Error shake with red glow
        withAnimation(.easeInOut(duration: 0.1).repeatCount(4, autoreverses: true)) {
            pulseScale = 1.08
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            glowOpacity = 0.7
            shadowRadius = 10
        }

        // Fade error effects
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.4)) {
                self.glowOpacity = 0.0
                self.shadowRadius = 2
                self.pulseScale = 1.0
            }
        }

        withAnimation(enhancedStateAnimation) {
            rotationAngle = .zero
            breathingScale = 1.0
            particleOpacity = 0.0
        }
    }
}

// MARK: - Recording State

/// Represents the current state of the recording system
public enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case completed
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