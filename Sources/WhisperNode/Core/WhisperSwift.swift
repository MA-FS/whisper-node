import Foundation
import WhisperBridge

/// Swift wrapper for Rust whisper FFI
public class WhisperSwift {
    private var handle: OpaquePointer?
    
    public init?(modelPath: String) {
        guard let cPath = modelPath.cString(using: .utf8) else {
            return nil
        }
        
        #if RUST_FFI_ENABLED
        handle = whisper_init(cPath)
        guard handle != nil else {
            return nil
        }
        #else
        handle = OpaquePointer(bitPattern: 0x1) // Placeholder non-null handle
        #endif
    }
    
    deinit {
        if let handle = handle {
            #if RUST_FFI_ENABLED
            whisper_free(handle)
            #endif
        }
    }
    
    /// Transcribe audio data
    /// - Parameter audioData: Array of f32 audio samples at 16kHz mono
    /// - Returns: Transcribed text or nil if failed
    public func transcribe(audioData: [Float]) -> String? {
        guard let handle = handle else { return nil }
        guard !audioData.isEmpty else { return nil }
        
        #if RUST_FFI_ENABLED
        let result = audioData.withUnsafeBufferPointer { buffer in
            whisper_transcribe(handle, buffer.baseAddress, buffer.count)
        }
        
        defer {
            // Clean up memory
            if result.text != nil {
                whisper_free_string(result.text)
            }
            if result.error != nil {
                whisper_free_string(result.error)
            }
        }
        
        guard result.success else {
            if let errorPtr = result.error {
                let errorString = String(cString: errorPtr)
                print("Whisper transcription error: \(errorString)")
            }
            return nil
        }
        
        guard let textPtr = result.text else {
            return nil
        }
        
        return String(cString: textPtr)
        #else
        
        // Placeholder implementation
        return "FFI placeholder - Rust integration pending"
        #endif
    }
}

/// Result structure for transcription
public struct TranscriptionResult {
    public let text: String
    public let success: Bool
    public let error: String?
    
    public init(text: String = "", success: Bool, error: String? = nil) {
        self.text = text
        self.success = success
        self.error = error
    }
}

/// Extended whisper wrapper with async support
public actor WhisperEngine {
    private let whisper: WhisperSwift
    
    public init?(modelPath: String) {
        guard let whisper = WhisperSwift(modelPath: modelPath) else {
            return nil
        }
        self.whisper = whisper
    }
    
    /// Async transcription with proper error handling
    public func transcribe(audioData: [Float]) async -> TranscriptionResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: TranscriptionResult(
                        success: false, 
                        error: "WhisperEngine deallocated"
                    ))
                    return
                }
                
                if let text = self.whisper.transcribe(audioData: audioData) {
                    continuation.resume(returning: TranscriptionResult(
                        text: text,
                        success: true
                    ))
                } else {
                    continuation.resume(returning: TranscriptionResult(
                        success: false,
                        error: "Transcription failed"
                    ))
                }
            }
        }
    }
}