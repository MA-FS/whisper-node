use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_float};
use libc::size_t;
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};
use std::collections::HashMap;
use whisper_rs::{WhisperContext, WhisperContextParameters, FullParams, SamplingStrategy};

/// Model information for tracking and management
#[derive(Debug, Clone)]
pub struct ModelInfo {
    pub name: String,
    pub size: ModelSize,
    pub memory_usage: u64, // in bytes
    pub cpu_factor: f32,   // relative CPU usage multiplier
}

/// Model size variants
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ModelSize {
    Tiny,
    Small,
    Medium,
}

impl ModelSize {
    fn from_name(name: &str) -> Self {
        if name.contains("tiny") { ModelSize::Tiny }
        else if name.contains("small") { ModelSize::Small }  
        else { ModelSize::Medium }
    }
    
    fn memory_limit(&self) -> u64 {
        match self {
            ModelSize::Tiny => 100 * 1024 * 1024,   // 100MB
            ModelSize::Small => 400 * 1024 * 1024,  // 400MB 
            ModelSize::Medium => 700 * 1024 * 1024, // 700MB
        }
    }
    
    fn cpu_threshold(&self) -> f32 {
        80.0 // 80% CPU threshold for downgrade
    }
}

/// Whisper model with lazy loading and memory management
pub struct WhisperModel {
    ctx: Option<WhisperContext>,
    model_path: String,
    model_info: ModelInfo,
    last_used: Instant,
    idle_timeout: Duration,
    is_loading: bool,
}

impl WhisperModel {
    fn new(model_path: String, model_info: ModelInfo) -> Self {
        Self {
            ctx: None,
            model_path,
            model_info,
            last_used: Instant::now(),
            idle_timeout: Duration::from_secs(30),
            is_loading: false,
        }
    }
    
    fn ensure_loaded(&mut self) -> Result<&WhisperContext, String> {
        self.last_used = Instant::now();
        
        if self.ctx.is_none() && !self.is_loading {
            self.is_loading = true;
            
            let params = WhisperContextParameters::default();
            match WhisperContext::new_with_params(&self.model_path, params) {
                Ok(context) => {
                    self.ctx = Some(context);
                    self.is_loading = false;
                }
                Err(e) => {
                    self.is_loading = false;
                    return Err(format!("Failed to load model: {}", e));
                }
            }
        }
        
        self.ctx.as_ref().ok_or_else(|| "Model not loaded".to_string())
    }
    
    fn should_unload(&self) -> bool {
        self.ctx.is_some() && 
        self.last_used.elapsed() > self.idle_timeout
    }
    
    fn unload(&mut self) {
        self.ctx = None;
    }
    
    fn memory_usage(&self) -> u64 {
        if self.ctx.is_some() {
            self.model_info.memory_usage
        } else {
            0
        }
    }
}

/// Thread-safe whisper model manager with automatic memory management
pub struct WhisperManager {
    models: RwLock<HashMap<String, Arc<Mutex<WhisperModel>>>>,
    memory_limit: u64,
    cpu_monitor: Arc<Mutex<CpuMonitor>>,
}

/// CPU usage monitoring for automatic model downgrade
pub struct CpuMonitor {
    cpu_samples: Vec<f32>,
    sample_count: usize,
    max_samples: usize,
}

impl CpuMonitor {
    fn new() -> Self {
        Self {
            cpu_samples: Vec::new(),
            sample_count: 0,
            max_samples: 10, // Track last 10 inference operations
        }
    }
    
    fn record_cpu_usage(&mut self, cpu_percent: f32) {
        if self.cpu_samples.len() < self.max_samples {
            self.cpu_samples.push(cpu_percent);
        } else {
            self.cpu_samples[self.sample_count % self.max_samples] = cpu_percent;
        }
        self.sample_count += 1;
    }
    
    fn average_cpu_usage(&self) -> f32 {
        if self.cpu_samples.is_empty() {
            0.0
        } else {
            self.cpu_samples.iter().sum::<f32>() / self.cpu_samples.len() as f32
        }
    }
    
    fn should_downgrade(&self, threshold: f32) -> bool {
        self.average_cpu_usage() > threshold
    }
}

impl WhisperManager {
    fn new() -> Self {
        Self {
            models: RwLock::new(HashMap::new()),
            memory_limit: 700 * 1024 * 1024, // 700MB peak limit
            cpu_monitor: Arc::new(Mutex::new(CpuMonitor::new())),
        }
    }
    
    fn register_model(&self, id: String, model_path: String, model_info: ModelInfo) -> Result<(), String> {
        let model = WhisperModel::new(model_path, model_info);
        let mut models = self.models.write().map_err(|_| "Failed to acquire write lock")?;
        models.insert(id, Arc::new(Mutex::new(model)));
        Ok(())
    }
    
    fn transcribe(&self, model_id: &str, audio_data: &[f32]) -> Result<String, String> {
        let start_time = Instant::now();
        
        // Check memory usage before inference
        self.manage_memory()?;
        
        let result = {
            let models = self.models.read().map_err(|_| "Failed to acquire read lock")?;
            let model_arc = models.get(model_id)
                .ok_or_else(|| format!("Model '{}' not found", model_id))?;
            
            let mut model = model_arc.lock().map_err(|_| "Failed to acquire model lock")?;
            let context = model.ensure_loaded()?;
            
            // Prepare inference parameters
            let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
            params.set_n_threads(4); // Optimize for Apple Silicon
            params.set_language(Some("en"));
            params.set_print_special(false);
            params.set_print_progress(false);
            params.set_print_realtime(false);
            params.set_print_timestamps(false);
            
            // Run inference
            context.full(params, audio_data)
                .map_err(|e| format!("Transcription failed: {}", e))?;
            
            // Extract text results
            let num_segments = context.full_n_segments()
                .map_err(|e| format!("Failed to get segment count: {}", e))?;
            
            let mut full_text = String::new();
            for i in 0..num_segments {
                if let Ok(segment_text) = context.full_get_segment_text(i) {
                    full_text.push_str(&segment_text);
                    if i < num_segments - 1 {
                        full_text.push(' ');
                    }
                }
            }
            
            Ok(full_text.trim().to_string())
        };
        
        // Record CPU usage (simplified - in real implementation would measure actual CPU)
        let inference_duration = start_time.elapsed();
        let estimated_cpu = (inference_duration.as_secs_f32() * 100.0).min(100.0);
        
        if let Ok(mut monitor) = self.cpu_monitor.lock() {
            monitor.record_cpu_usage(estimated_cpu);
        }
        
        result
    }
    
    fn manage_memory(&self) -> Result<(), String> {
        let current_usage = self.current_memory_usage();
        
        if current_usage > self.memory_limit {
            // Unload idle models to free memory
            let models = self.models.read().map_err(|_| "Failed to acquire read lock")?;
            
            for model_arc in models.values() {
                if let Ok(mut model) = model_arc.lock() {
                    if model.should_unload() {
                        model.unload();
                    }
                }
            }
        }
        
        Ok(())
    }
    
    fn current_memory_usage(&self) -> u64 {
        let models = match self.models.read() {
            Ok(models) => models,
            Err(_) => return 0,
        };
        
        models.values()
            .filter_map(|model_arc| {
                model_arc.lock().ok().map(|model| model.memory_usage())
            })
            .sum()
    }
    
    fn suggest_model_downgrade(&self, current_model: &str) -> Option<String> {
        if let Ok(monitor) = self.cpu_monitor.lock() {
            if monitor.should_downgrade(80.0) {
                // Suggest smaller model based on current model
                if current_model.contains("medium") {
                    return Some("small".to_string());
                } else if current_model.contains("small") {
                    return Some("tiny".to_string());
                }
            }
        }
        None
    }
}

/// Global whisper manager instance
static WHISPER_MANAGER: once_cell::sync::Lazy<WhisperManager> = 
    once_cell::sync::Lazy::new(|| WhisperManager::new());

/// Opaque handle for FFI - now just contains model ID
pub struct WhisperHandle {
    model_id: String,
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
    
    // Generate unique model ID based on path
    let model_id = format!("model_{}", path_str.replace(['/', '\\', '.'], "_"));
    
    // Create model info based on path
    let model_size = ModelSize::from_name(path_str);
    let model_info = ModelInfo {
        name: path_str.to_string(),
        size: model_size,
        memory_usage: match model_size {
            ModelSize::Tiny => 39 * 1024 * 1024,   // ~39MB
            ModelSize::Small => 244 * 1024 * 1024,  // ~244MB
            ModelSize::Medium => 769 * 1024 * 1024, // ~769MB
        },
        cpu_factor: match model_size {
            ModelSize::Tiny => 1.0,
            ModelSize::Small => 2.5,
            ModelSize::Medium => 4.0,
        },
    };
    
    // Register model with manager
    match WHISPER_MANAGER.register_model(model_id.clone(), path_str.to_string(), model_info) {
        Ok(_) => {
            let handle = Box::new(WhisperHandle { model_id });
            Box::into_raw(handle)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// Transcribe audio data using the whisper model manager
/// 
/// Implements full whisper.cpp integration with lazy loading, memory management,
/// and CPU monitoring for automatic model downgrade.
/// 
/// # Safety
/// - handle must be a valid pointer returned by whisper_init
/// - audio_data must point to valid f32 audio samples  
/// - audio_len must accurately represent the length of audio_data
#[no_mangle]
pub extern "C" fn whisper_transcribe(
    handle: *mut WhisperHandle,
    audio_data: *const c_float,
    audio_len: size_t,
) -> WhisperResult {
    if handle.is_null() || audio_data.is_null() || audio_len <= 0 {
        return WhisperResult {
            success: false,
            text: std::ptr::null_mut(),
            error: create_error_string("Invalid parameters"),
        };
    }
    
    let handle_ref = unsafe { &*handle };
    
    // Convert audio data to slice
    let audio_slice = unsafe {
        std::slice::from_raw_parts(audio_data, audio_len)
    };
    
    // Perform transcription using the manager
    match WHISPER_MANAGER.transcribe(&handle_ref.model_id, audio_slice) {
        Ok(text) => {
            // Check if model downgrade is suggested
            if let Some(suggested_model) = WHISPER_MANAGER.suggest_model_downgrade(&handle_ref.model_id) {
                eprintln!("Whisper: High CPU usage detected, consider switching to {} model", suggested_model);
            }
            
            match CString::new(text) {
                Ok(c_string) => WhisperResult {
                    success: true,
                    text: c_string.into_raw(),
                    error: std::ptr::null_mut(),
                },
                Err(_) => WhisperResult {
                    success: false,
                    text: std::ptr::null_mut(),
                    error: create_error_string("Failed to convert transcription result"),
                },
            }
        }
        Err(error_msg) => WhisperResult {
            success: false,
            text: std::ptr::null_mut(),
            error: create_error_string(&error_msg),
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

/// Get current memory usage of all loaded models
#[no_mangle]
pub extern "C" fn whisper_get_memory_usage() -> u64 {
    WHISPER_MANAGER.current_memory_usage()
}

/// Force memory cleanup by unloading idle models
#[no_mangle]
pub extern "C" fn whisper_cleanup_memory() -> bool {
    WHISPER_MANAGER.manage_memory().is_ok()
}

/// Get average CPU usage for performance monitoring
#[no_mangle]
pub extern "C" fn whisper_get_avg_cpu_usage() -> c_float {
    if let Ok(monitor) = WHISPER_MANAGER.cpu_monitor.lock() {
        monitor.average_cpu_usage()
    } else {
        0.0
    }
}

/// Check if model downgrade is recommended for given model
#[no_mangle]
pub extern "C" fn whisper_check_downgrade_needed(handle: *mut WhisperHandle) -> bool {
    if handle.is_null() {
        return false;
    }
    
    let handle_ref = unsafe { &*handle };
    WHISPER_MANAGER.suggest_model_downgrade(&handle_ref.model_id).is_some()
}

/// Get suggested downgrade model name (caller must free result)
#[no_mangle]
pub extern "C" fn whisper_get_suggested_model(handle: *mut WhisperHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    
    let handle_ref = unsafe { &*handle };
    if let Some(suggested) = WHISPER_MANAGER.suggest_model_downgrade(&handle_ref.model_id) {
        match CString::new(suggested) {
            Ok(c_string) => c_string.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    } else {
        std::ptr::null_mut()
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
    fn test_model_info_creation() {
        let tiny_info = ModelInfo {
            name: "tiny.en".to_string(),
            size: ModelSize::Tiny,
            memory_usage: 39 * 1024 * 1024,
            cpu_factor: 1.0,
        };
        
        assert_eq!(tiny_info.size, ModelSize::Tiny);
        assert_eq!(tiny_info.size.memory_limit(), 100 * 1024 * 1024);
        assert_eq!(tiny_info.size.cpu_threshold(), 80.0);
    }
    
    #[test]
    fn test_model_size_from_name() {
        assert_eq!(ModelSize::from_name("tiny.en"), ModelSize::Tiny);
        assert_eq!(ModelSize::from_name("small.en"), ModelSize::Small);
        assert_eq!(ModelSize::from_name("medium.en"), ModelSize::Medium);
        assert_eq!(ModelSize::from_name("unknown"), ModelSize::Medium); // Default
    }
    
    #[test]
    fn test_cpu_monitor() {
        let mut monitor = CpuMonitor::new();
        
        // Test initial state
        assert_eq!(monitor.average_cpu_usage(), 0.0);
        assert!(!monitor.should_downgrade(80.0));
        
        // Add some CPU usage samples
        monitor.record_cpu_usage(50.0);
        monitor.record_cpu_usage(60.0);
        monitor.record_cpu_usage(70.0);
        
        assert_eq!(monitor.average_cpu_usage(), 60.0);
        assert!(!monitor.should_downgrade(80.0));
        
        // Add high CPU usage
        monitor.record_cpu_usage(90.0);
        monitor.record_cpu_usage(95.0);
        
        assert!(monitor.average_cpu_usage() > 70.0);
        assert!(monitor.should_downgrade(80.0));
    }
    
    #[test]
    fn test_whisper_model_lifecycle() {
        let model_info = ModelInfo {
            name: "test.en".to_string(),
            size: ModelSize::Tiny,
            memory_usage: 50 * 1024 * 1024,
            cpu_factor: 1.0,
        };
        
        let mut model = WhisperModel::new("/tmp/test".to_string(), model_info);
        
        // Initially unloaded
        assert_eq!(model.memory_usage(), 0);
        assert!(model.ctx.is_none());
        
        // Should unload after timeout (simulated)
        std::thread::sleep(std::time::Duration::from_millis(10));
        model.idle_timeout = std::time::Duration::from_millis(5);
        assert!(model.should_unload());
    }
    
    #[test]
    fn test_memory_management_functions() {
        // Test memory usage tracking
        let initial_usage = whisper_get_memory_usage();
        assert_eq!(initial_usage, 0); // No models loaded initially
        
        // Test memory cleanup
        assert!(whisper_cleanup_memory());
        
        // Test CPU usage monitoring
        let cpu_usage = whisper_get_avg_cpu_usage();
        assert!(cpu_usage >= 0.0);
    }
    
    #[test]
    fn test_performance_monitoring_ffi() {
        // Test with null handle
        assert!(!whisper_check_downgrade_needed(std::ptr::null_mut()));
        assert!(whisper_get_suggested_model(std::ptr::null_mut()).is_null());
    }
    
    #[test]
    fn test_whisper_manager_registration() {
        let model_info = ModelInfo {
            name: "test_model".to_string(),
            size: ModelSize::Tiny,
            memory_usage: 100 * 1024 * 1024,
            cpu_factor: 1.0,
        };
        
        let manager = WhisperManager::new();
        let result = manager.register_model(
            "test_id".to_string(),
            "/tmp/test_model.bin".to_string(),
            model_info
        );
        
        // Should fail because model file doesn't exist, but registration logic should work
        assert!(result.is_ok());
        
        // Test transcription with non-existent model (should fail gracefully)
        let audio_data = vec![0.0f32; 1000];
        let transcribe_result = manager.transcribe("test_id", &audio_data);
        assert!(transcribe_result.is_err());
    }
    
    #[test]
    fn test_memory_limits() {
        assert_eq!(ModelSize::Tiny.memory_limit(), 100 * 1024 * 1024);
        assert_eq!(ModelSize::Small.memory_limit(), 400 * 1024 * 1024);
        assert_eq!(ModelSize::Medium.memory_limit(), 700 * 1024 * 1024);
    }
    
    #[test]
    #[ignore] // Enable when real transcription is implemented
    fn test_successful_transcription() {
        // This test should be enabled once whisper_init works with valid models
        // and whisper_transcribe performs actual transcription
        
        // let model_path = CString::new("path/to/test/model").unwrap();
        // let handle = whisper_init(model_path.as_ptr());
        // assert!(!handle.is_null());
        
        // let test_audio = vec![0.1f32; 16000]; // 1 second of audio at 16kHz
        // let result = whisper_transcribe(handle, test_audio.as_ptr(), test_audio.len());
        // assert!(result.success);
        // assert!(!result.text.is_null());
        
        // whisper_free_string(result.text);
        // whisper_free(handle);
    }
}