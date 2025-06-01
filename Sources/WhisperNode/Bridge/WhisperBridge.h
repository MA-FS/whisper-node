#ifndef WhisperBridge_h
#define WhisperBridge_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque pointer to Rust WhisperHandle
typedef struct WhisperHandle WhisperHandle;

// FFI-safe result structure matching Rust definition
typedef struct {
    bool success;
    char* text;
    char* error;
} WhisperResult;

// Initialize whisper context with model path
WhisperHandle* whisper_init(const char* model_path);

// Transcribe audio data (f32 array, length)
WhisperResult whisper_transcribe(WhisperHandle* handle, const float* audio_data, int audio_len);

// Free whisper context
void whisper_free(WhisperHandle* handle);

// Free result strings
void whisper_free_string(char* ptr);

#ifdef __cplusplus
}
#endif

#endif /* WhisperBridge_h */