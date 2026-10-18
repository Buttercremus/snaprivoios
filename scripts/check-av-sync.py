#!/usr/bin/env python3
"""Measure optical flashes vs decoded 1-kHz onsets; local ffmpeg/ffprobe only.

Use with the synthetic AVSyncFixture, never arbitrary user media. Positive
offset means audio follows the visible flash. No upload or external service.
"""
import argparse
import array
import json
import math
import statistics
import subprocess
from pathlib import Path


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def frames(path, selector):
    return json.loads(run('ffprobe', '-v', 'error', '-select_streams', selector,
        '-show_frames', '-show_entries', 'frame=best_effort_timestamp_time,nb_samples',
        '-of', 'json', str(path)))['frames']


def video_onsets(path):
    timing = frames(path, 'v:0')
    pixels = run('ffmpeg', '-v', 'error', '-i', str(path), '-map', '0:v:0', '-an',
        '-vf', 'crop=100:100:(in_w-100)/2:(in_h-100)/2,scale=1:1',
        '-fps_mode', 'passthrough', '-pix_fmt', 'gray', '-f', 'rawvideo', '-')
    if len(pixels) != len(timing):
        raise ValueError('Decoded video and timestamp count differ')
    found, was_bright = [], False
    for pixel, frame in zip(pixels, timing):
        bright = pixel > 180
        if bright and not was_bright:
            found.append(float(frame['best_effort_timestamp_time']))
        was_bright = bright
    return found


def audio_onsets(path, index, sample_rate=48_000):
    timing = frames(path, f'a:{index}')
    if not timing:
        raise ValueError('No decoded audio frames')
    # Reject discontinuous timestamps rather than pretending samples are uniform.
    first = float(timing[0]['best_effort_timestamp_time'])
    count = 0
    for frame in timing:
        expected = first + count / sample_rate
        if abs(float(frame['best_effort_timestamp_time']) - expected) > 0.003:
            raise ValueError('Audio timestamps have a gap larger than 3 ms')
        count += int(frame['nb_samples'])
    samples = array.array('f', run('ffmpeg', '-v', 'error', '-i', str(path), '-map', f'0:a:{index}',
        '-vn', '-ac', '1', '-ar', '48000', '-c:a', 'pcm_f32le', '-f', 'f32le', '-'))
    block = 240  # 5 ms; phase-independent magnitude at exactly 1 kHz.
    sine = [math.sin(2 * math.pi * 1000 * i / 48_000) for i in range(block)]
    cosine = [math.cos(2 * math.pi * 1000 * i / 48_000) for i in range(block)]
    magnitudes = []
    for start in range(0, len(samples) - block + 1, block):
        values = samples[start:start + block]
        real = sum(x * y for x, y in zip(values, cosine))
        imaginary = sum(x * y for x, y in zip(values, sine))
        magnitude = 2 * math.hypot(real, imaginary) / block
        rms = math.sqrt(sum(x * x for x in values) / block)
        # A loud clap must not raise the tone threshold and hide quieter pulses.
        # A sine has magnitude / (sqrt(2) * RMS) == 1; broadband transients do not.
        purity = magnitude / (math.sqrt(2) * rms) if rms else 0
        magnitudes.append(magnitude if purity >= 0.65 else 0)
    peak = max(magnitudes, default=0)
    if peak < 0.0001:
        raise ValueError('No measurable 1-kHz test tone')
    threshold = max(0.0001, peak * 0.25)
    found, active = [], None
    for i, magnitude in enumerate(magnitudes + [0]):
        if magnitude >= threshold:
            if active is None:
                active = i
        elif active is not None:
            if i - active >= 3:  # Ignore short transients; accept >=15 ms.
                found.append(first + active * block / 48_000)
            active = None
    return found, peak


def compare(video, audio, limit=0.100):
    if len(video) < 6:
        raise ValueError('At least six optical pulses are required')
    pairs, used = [], set()
    for timestamp in video:
        candidates = [(abs(value - timestamp), i, value) for i, value in enumerate(audio)
            if i not in used and abs(value - timestamp) <= 0.4]
        if not candidates:
            raise ValueError(f'No audio pulse matched optical pulse at {timestamp:.3f} s')
        _, index, value = min(candidates)
        used.add(index)
        pairs.append({'video_s': timestamp, 'audio_s': value, 'offset_ms': (value - timestamp) * 1000})
    offsets = [item['offset_ms'] for item in pairs]
    third = max(1, len(offsets) // 3)
    sections = [offsets[:third], offsets[third:-third], offsets[-third:]]
    return {'passed': max(map(abs, offsets)) <= limit * 1000, 'pairs': pairs,
        'median_ms': statistics.median(offsets), 'max_absolute_ms': max(map(abs, offsets)),
        'begin_middle_end_median_ms': [statistics.median(part) for part in sections],
        'drift_ms': statistics.median(sections[-1]) - statistics.median(sections[0]),
        'unmatched_audio_pulses': len(audio) - len(used)}


def measure(path, limit):
    probe = json.loads(run('ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)))
    video = video_onsets(path)
    tracks = []
    for index, stream in enumerate(s for s in probe['streams'] if s['codec_type'] == 'audio'):
        onsets, peak = audio_onsets(path, index, int(stream['sample_rate']))
        result = compare(video, onsets, limit)
        result.update({'audio_stream_index': stream['index'], 'codec': stream['codec_name'],
            'sample_rate': stream.get('sample_rate'), 'channels': stream.get('channels'),
            'peak_tone_amplitude': peak})
        tracks.append(result)
    if not tracks:
        raise ValueError('Recording has no audio track')
    return {'file': str(path), 'duration_s': float(probe['format']['duration']),
        'video_tracks': [{key: stream.get(key) for key in ('codec_name', 'width', 'height', 'duration', 'nb_frames')}
            for stream in probe['streams'] if stream['codec_type'] == 'video'],
        'limit_ms': limit * 1000, 'optical_pulses': len(video), 'audio_tracks': tracks,
        'passed': all(track['passed'] for track in tracks),
        'measurement_resolution': 'video frame cadence plus 5 ms audio windows'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('movie', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--limit-ms', type=float, default=100)
    args = parser.parse_args()
    try:
        result = measure(args.movie, args.limit_ms / 1000)
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        result = {'file': str(args.movie), 'passed': False, 'error': str(error)}
    text = json.dumps(result, indent=2)
    if args.output:
        args.output.write_text(text + '\n')
    print(text)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
