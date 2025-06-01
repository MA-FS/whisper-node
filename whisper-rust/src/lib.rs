use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_float};
use whisper_rs::{WhisperContext, WhisperContextParameters};

/// Opaque pointer to WhisperContext for FFI
pub struct WhisperHandle {
    context: WhisperContext,
}

/// FFI-safe result structure
#[repr(C)]
pub struct WhisperResult {
    pub success: bool,
    pub text: *mut c_char,
    pub error: *mut c_char,
}

/// Initialize whisper context with model path
#[no_mangle]
pub extern "C" fn whisper_init(model_path: *const c_char) -> *mut WhisperHandle {
    if model_path.is_null() {
        return std::ptr::null_mut();
    }
    
    let path_str = unsafe {
        match CStr::from_ptr(model_path).to_str() {
            Ok(s) => s,
            Err(_) => return std::ptr::null_mut(),
        }
    };
    
    let params = WhisperContextParameters::default();
    
    match WhisperContext::new_with_params(path_str, params) {
        Ok(context) => {
            let handle = Box::new(WhisperHandle { context });
            Box::into_raw(handle)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// Transcribe audio data (placeholder implementation)
#[no_mangle]
pub extern "C" fn whisper_transcribe(
    handle: *mut WhisperHandle,
    audio_data: *const c_float,
    audio_len: c_int,
) -> WhisperResult {
    if handle.is_null() || audio_data.is_null() || audio_len <= 0 {
        return WhisperResult {
            success: false,
            text: std::ptr::null_mut(),
            error: create_error_string("Invalid parameters"),
        };
    }
    
    // For now, return a placeholder result until we can resolve the API
    let placeholder_text = "Transcription placeholder - API integration pending";
    match CString::new(placeholder_text) {
        Ok(c_string) => WhisperResult {
            success: true,
            text: c_string.into_raw(),
            error: std::ptr::null_mut(),
        },
        Err(_) => WhisperResult {
            success: false,
            text: std::ptr::null_mut(),
            error: create_error_string("Failed to create placeholder text"),
        },
    }
}

/// Free whisper context
#[no_mangle]
pub extern "C" fn whisper_free(handle: *mut WhisperHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

/// Free result strings
#[no_mangle]
pub extern "C" fn whisper_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

/// Helper function to create error C strings
fn create_error_string(msg: &str) -> *mut c_char {
    match CString::new(msg) {
        Ok(c_string) => c_string.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_ffi_safety() {
        // Test null pointer handling
        let result = whisper_transcribe(
            std::ptr::null_mut(),
            std::ptr::null(),
            0
        );
        assert!(!result.success);
        
        // Test context creation with invalid path
        let invalid_path = CString::new("invalid_path").unwrap();
        let handle = whisper_init(invalid_path.as_ptr());
        assert!(handle.is_null());
    }
    
    #[test]
    fn test_placeholder_transcription() {
        // Test placeholder functionality
        let test_audio = vec![0.0f32; 1000];
        let result = whisper_transcribe(
            std::ptr::null_mut(), // This will trigger placeholder
            test_audio.as_ptr(),
            test_audio.len() as c_int,
        );
        
        // Should fail with null handle
        assert!(!result.success);
        
        // Clean up
        if !result.error.is_null() {
            whisper_free_string(result.error);
        }
    }
}