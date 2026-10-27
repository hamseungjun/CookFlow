"""Reject non-speech WAV before ASR. VAD is evidence, never permission to advance."""
import array
import io
import math
from pathlib import Path
import sys
import wave
sys.path.insert(0, str(Path(__file__).with_name('vendor')))
import webrtcvad

def speech_evidence(audio, mime):
    if mime.split(';')[0] not in ('audio/wav', 'audio/x-wav'):
        try:
            import av
            resampler = av.AudioResampler(format='s16', layout='mono', rate=16000)
            pcm = bytearray()
            with av.open(io.BytesIO(audio)) as container:
                for frame in container.decode(audio=0):
                    for converted in resampler.resample(frame):
                        pcm.extend(bytes(converted.planes[0])[:converted.samples*2])
                        if len(pcm) > 16000 * 2 * 12:
                            return {'accepted': False, 'reason': 'recording_too_long'}
                for converted in resampler.resample(None):
                    pcm.extend(bytes(converted.planes[0])[:converted.samples*2])
            output = io.BytesIO()
            with wave.open(output, 'wb') as wav:
                wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(16000); wav.writeframes(pcm)
            return speech_evidence(output.getvalue(), 'audio/wav')
        except Exception:
            return {'accepted': False, 'reason': 'unverified_audio_format'}
    try:
        with wave.open(io.BytesIO(audio), 'rb') as wav:
            channels, width, rate = wav.getnchannels(), wav.getsampwidth(), wav.getframerate()
            if width != 2 or channels not in (1, 2) or not 8000 <= rate <= 96000 or wav.getnframes() > rate * 12:
                return {'accepted': False, 'reason': 'unsupported_pcm'}
            samples = array.array('h', wav.readframes(wav.getnframes()))
    except (wave.Error, EOFError):
        return {'accepted': False, 'reason': 'invalid_wav'}
    if channels == 2:
        samples = array.array('h', (int((samples[i] + samples[i+1]) / 2) for i in range(0, len(samples)-1, 2)))
    if rate not in (8000, 16000, 32000, 48000):
        target = 16000
        resampled = array.array('h')
        for i in range(int(len(samples) * target / rate)):
            position = i * rate / target; left = int(position); weight = position-left
            if left+1 < len(samples): resampled.append(round(samples[left]*(1-weight)+samples[left+1]*weight))
        samples, rate = resampled, target
    pcm = samples.tobytes(); frame_size = int(rate * .02) * 2
    vad = webrtcvad.Vad(3)
    flags = [vad.is_speech(pcm[i:i+frame_size], rate) for i in range(0, len(pcm)-frame_size+1, frame_size)]
    voiced = sum(flags)
    levels = []
    for index, flag in enumerate(flags):
        if flag:
            block = samples[index * (frame_size//2):(index+1) * (frame_size//2)]
            levels.append(math.sqrt(sum(v*v for v in block) / max(1,len(block))))
    levels.sort()
    contrast = levels[int((len(levels)-1)*.9)] / max(1,levels[int((len(levels)-1)*.1)]) if levels else 0
    longest = run = 0
    for flag in flags:
        run = run+1 if flag else 0; longest = max(longest, run)
    accepted = voiced >= 12 and longest >= 10 and voiced / max(1,len(flags)) >= .10 and contrast >= 1.25
    return {'accepted': accepted, 'reason': 'speech' if accepted else 'no_sustained_speech', 'voiced_ms': voiced*20, 'longest_ms':longest*20, 'energy_contrast':round(contrast,2)}
