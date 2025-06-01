# Task 06: Whisper Model Integration

**Status**: ⏳ WIP  
**Priority**: High  
**Estimated Hours**: 18  
**Dependencies**: T02, T04  

## Description

Integrate whisper.cpp with lazy loading, memory management, and model switching capabilities.

## Acceptance Criteria

- [ ] whisper.cpp integration with Rust FFI
- [ ] Lazy model loading with 30s idle unload
- [ ] Memory management: ≤100MB idle, ≤700MB peak
- [ ] Model switching with app restart requirement
- [ ] Automatic model downgrade if >80% CPU
- [ ] Atomic model file handling

## Implementation Details

### whisper.cpp Integration
- Load models via Rust FFI bridge
- Support for tiny.en, small.en, medium.en models
- Apple Silicon optimized inference

### Memory Management
```rust
pub struct WhisperModel {
    ctx: Option<WhisperContext>,
    last_used: Instant,
    idle_timeout: Duration,
}
```

### Lazy Loading Strategy
- Load model on first inference request
- Unload after 30 seconds of inactivity
- Preload during app startup for faster first use

### Performance Monitoring
- Track CPU usage during inference
- Automatic downgrade to smaller model if >80% CPU
- Memory usage tracking and limits

## Testing Plan

- [ ] Model loading/unloading works correctly
- [ ] Memory usage stays within limits
- [ ] CPU monitoring triggers downgrades
- [ ] Inference accuracy meets requirements

## Tags
`whisper`, `ml`, `memory`, `performance`