# Test Audio Resources

This directory contains audio files used for performance testing.

## Required Test Audio Files

For accurate performance testing, place the following files in this directory:

- `test_audio_3s.wav` - 3-second speech sample (16kHz mono, 16-bit)
- `test_audio_5s.wav` - 5-second speech sample (16kHz mono, 16-bit)  
- `test_audio_10s.wav` - 10-second speech sample (16kHz mono, 16-bit)
- `test_audio_15s.wav` - 15-second speech sample (16kHz mono, 16-bit)

## Audio Format Requirements

- **Sample Rate**: 16kHz
- **Channels**: Mono
- **Bit Depth**: 16-bit
- **Format**: WAV (uncompressed)
- **Content**: Clear English speech without background noise

## Generating Test Audio

If real test audio is not available, you can generate synthetic test files using:

```bash
# Example using ffmpeg to create test audio
ffmpeg -f lavfi -i "sine=frequency=440:duration=5" -ar 16000 -ac 1 -y test_audio_5s.wav
```

Note: Synthetic audio will not provide accurate transcription accuracy testing but can be used for latency and resource usage validation.

## Privacy & Licensing

- Do not commit personal voice recordings
- Use only public domain or appropriately licensed audio content
- Consider using Common Voice or LibriSpeech samples for accuracy testing