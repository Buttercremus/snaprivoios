#!/usr/bin/env python3
"""Decode the silent moving V04 fixture; never analyzes audio or uploads media."""
import argparse
import json
import statistics
import subprocess
from pathlib import Path


def probe(*args):
    return json.loads(subprocess.run(['ffprobe', '-v', 'error', *args, '-of', 'json'],
        check=True, capture_output=True).stdout)


def measure(path, minimum_duration=900):
    media = probe('-show_streams', '-show_format', str(path))
    videos = [s for s in media['streams'] if s['codec_type'] == 'video']
    if len(videos) != 1:
        raise ValueError('Exactly one video track required')
    stream = videos[0]
    duration = float(stream.get('duration', media['format']['duration']))
    audio_count = sum(s['codec_type'] == 'audio' for s in media['streams'])
    timing = probe('-select_streams', 'v:0', '-show_frames', '-show_entries',
        'frame=best_effort_timestamp_time', str(path))['frames']
    times = [float(f['best_effort_timestamp_time']) for f in timing]
    if len(times) < 2:
        raise ValueError('Too few decoded frames')
    gaps = [b-a for a, b in zip(times, times[1:])]
    if min(gaps) <= 0:
        raise ValueError('Video timestamps are not strictly increasing')
    # Decode every frame, but keep only a small, bounded grayscale buffer. The
    # fixture changes its background each tick; long identical runs are invalid.
    command = ['ffmpeg', '-v', 'error', '-threads', '2', '-i', str(path), '-map', '0:v:0', '-an',
        '-vf', 'scale=16:9:flags=area', '-fps_mode', 'passthrough', '-pix_fmt', 'gray', '-f', 'rawvideo', '-']
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    previous = None
    still_start = None
    max_still = 0.0
    motion_frames = 0
    decoded = 0
    try:
        while True:
            pixels = process.stdout.read(144)
            if not pixels:
                break
            if len(pixels) != 144 or decoded >= len(times):
                raise ValueError('Decoded pixels and timestamps differ')
            if previous is not None:
                difference = sum(abs(a-b) for a,b in zip(pixels, previous)) / 144
                if difference < 0.15:
                    if still_start is None:
                        still_start = times[decoded-1]
                    max_still = max(max_still, times[decoded]-still_start)
                else:
                    motion_frames += 1
                    still_start = None
            previous = pixels
            decoded += 1
        errors = process.stderr.read().decode(errors='replace')
        if process.wait() != 0:
            raise ValueError('Video decode failed: '+errors[:1000])
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close(); process.stderr.close()
    if decoded != len(times):
        raise ValueError('Decoded pixels and timestamps differ')
    average_fps = decoded/duration
    sections = []
    for i in range(3):
        start, end = duration*i/3, duration*(i+1)/3
        section = [t for t in times if start <= t < end]
        sections.append({'start_s':start, 'end_s':end, 'frames':len(section), 'average_fps':len(section)/(end-start)})
    criteria = {
        'duration': duration >= minimum_duration,
        'silent': audio_count == 0,
        'h264': stream['codec_name'] == 'h264',
        'dimensions': 0 < stream['width'] <= 1920 and 0 < stream['height'] <= 1080 and stream['width']%2 == stream['height']%2 == 0,
        'average_at_least_29_fps': average_fps >= 29,
        'median_30_fps': abs(statistics.median(gaps)-1/30) <= 0.002,
        'timestamp_gap_at_most_250_ms': max(gaps) <= 0.250,
        'moving_fixture_stall_at_most_500_ms': max_still <= 0.500,
    }
    return {'file':str(path), 'duration_s':duration, 'width':stream['width'], 'height':stream['height'],
        'codec':stream['codec_name'], 'audio_tracks':audio_count, 'decoded_frames':decoded,
        'average_fps':average_fps, 'median_frame_interval_ms':statistics.median(gaps)*1000,
        'max_timestamp_gap_ms':max(gaps)*1000, 'max_static_run_ms':max_still*1000,
        'motion_frame_transitions':motion_frames, 'begin_middle_end':sections,
        'criteria':criteria, 'passed':all(criteria.values()),
        'scope':'Silent moving fixture only. No audio or A/V synchronization measured.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('movie', type=Path)
    parser.add_argument('--min-duration', type=float, default=900)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        if args.min_duration <= 0:
            raise ValueError('Positive minimum duration required')
        result = measure(args.movie, args.min_duration)
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        result = {'file':str(args.movie), 'passed':False, 'error':str(error)}
    text = json.dumps(result, indent=2)
    if args.output:
        args.output.write_text(text+'\n')
    print(text)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
