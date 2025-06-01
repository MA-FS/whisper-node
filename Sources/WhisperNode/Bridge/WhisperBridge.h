#ifndef WhisperBridge_h
#define WhisperBridge_h

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque pointer to Rust WhisperHandle
typedef struct WhisperHandle WhisperHandle;

// FFI-safe result structure matching Rust definition
// Note: caller is responsible for freeing 'text' and 'error' using whisper_free_string()
typedef struct {
    bool success;
    char* text;   // Transcribed text (NULL if success=false)
    char* error;  // Error message (NULL if success=true)
} WhisperResult;

// Initialize whisper context with model path
WhisperHandle* whisper_init(const char* model_path);

// Transcribe audio data (f32 array, length)
WhisperResult whisper_transcribe(WhisperHandle* handle, const float* audio_data, size_t audio_len);

// Free whisper context
void whisper_free(WhisperHandle* handle);

// Free result strings
void whisper_free_string(char* ptr);

#ifdef __cplusplus
}
#endif

#endif /* WhisperBridge_h */