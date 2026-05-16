"""
Enhanced 5-band + beat audio analyzer for Quantum Dance.
Outputs .quantum JSON with: sub_bass, bass, mid, high, air + onset, rms, centroid, tempo
Usage: python3 audio_bands.py <input_audio> [output_json]
"""
import json, sys, os
import numpy as np
import librosa


def extract_bands(y, sr, hop_length=512):
    """Extract 5 frequency bands + onset + rms + centroid"""
    
    # --- Helper: average energy in a frequency range per frame ---
    def band_energy(fmin, fmax):
        spec = np.abs(librosa.stft(y, hop_length=hop_length))
        freqs = librosa.fft_frequencies(sr=sr)
        mask = (freqs >= fmin) & (freqs <= fmax)
        return np.sum(spec[mask], axis=0)

    # --- 5 Frequency Bands ---
    sub_bass = band_energy(20, 60)     # sub-bass rumble
    bass     = band_energy(60, 250)    # bass punch
    mid      = band_energy(250, 2000)  # mids (vocals, instruments)
    high     = band_energy(2000, 8000) # highs (presence, clarity)
    air      = band_energy(8000, 20000)# air/sparkle

    # --- Onset (beat detection) ---
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop_length)

    # --- RMS (overall loudness) ---
    rms = librosa.feature.rms(y=y, hop_length=hop_length)[0]

    # --- Spectral Centroid ---
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop_length)[0]

    # --- Normalize all to 0-1 ---
    def safe_norm(arr):
        arr = arr.astype(np.float64)
        mn, mx = arr.min(), arr.max()
        if mx - mn < 1e-10: return np.zeros_like(arr)
        return (arr - mn) / (mx - mn)

    num_frames = len(onset_env)

    return {
        'sub_bass': safe_norm(sub_bass[:num_frames]).tolist(),
        'bass':     safe_norm(bass[:num_frames]).tolist(),
        'mid':      safe_norm(mid[:num_frames]).tolist(),
        'high':     safe_norm(high[:num_frames]).tolist(),
        'air':      safe_norm(air[:num_frames]).tolist(),
        'onset':    safe_norm(onset_env).tolist(),
        'rms':      safe_norm(rms[:num_frames]).tolist(),
        'centroid': safe_norm(centroid[:num_frames]).tolist(),
        'num_frames': int(num_frames),
        'fps': float(sr / hop_length),
        'duration': float(len(y) / sr),
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 audio_bands.py <input_audio> [output_json]")
        sys.exit(1)

    inpath = sys.argv[1]
    outpath = sys.argv[2] if len(sys.argv) > 2 else inpath.rsplit('.', 1)[0] + '.quantum'

    print(f"Loading: {inpath}")
    y, sr = librosa.load(inpath, sr=None)
    print(f"Sample rate: {sr}, Duration: {len(y)/sr:.1f}s")

    print("Extracting 5-band data...")
    data = extract_bands(y, sr)

    with open(outpath, 'w') as f:
        json.dump(data, f)

    size_mb = os.path.getsize(outpath) / (1024*1024)
    print(f"Saved: {outpath} ({size_mb:.2f} MB, {data['num_frames']} frames @ {data['fps']:.1f} fps)")


if __name__ == '__main__':
    main()
