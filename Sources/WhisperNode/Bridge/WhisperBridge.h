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

// Memory management functions
uint64_t whisper_get_memory_usage(void);
bool whisper_cleanup_memory(void);

// Performance monitoring functions  
float whisper_get_avg_cpu_usage(void);
bool whisper_check_downgrade_needed(WhisperHandle* handle);
char* whisper_get_suggested_model(WhisperHandle* handle);

#ifdef __cplusplus
}
#endif

#endif /* WhisperBridge_h */