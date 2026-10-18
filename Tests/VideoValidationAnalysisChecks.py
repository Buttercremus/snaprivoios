"""Independent silent fixtures for the V04 full-video decoder."""
import importlib.util
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('silent_video', root/'scripts/check-silent-video.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

with tempfile.TemporaryDirectory(prefix='Snaprivo-Silent-Analysis-') as folder:
    def movie(name, filters=None):
        path = Path(folder)/name
        args = ['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=30:duration=2']
        if filters:
            args += ['-vf', filters]
        subprocess.run(args+['-fps_mode', 'vfr', '-an', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(path)], check=True)
        return path
    good = movie('Moving.mp4')
    assert module.measure(good, 1.9)['passed']
    assert not module.measure(good, 900)['criteria']['duration']
    frozen = movie('Frozen.mp4', 'tpad=stop_mode=clone:stop_duration=1')
    result = module.measure(frozen, 1.9)
    assert not result['passed'] and result['max_static_run_ms'] >= 900
    missing = movie('MissingFrames.mp4', "select='not(between(n,20,30))'")
    result = module.measure(missing, 1.9)
    assert not result['passed'] and result['max_timestamp_gap_ms'] > 250
    broken = Path(folder)/'Broken.mp4'; broken.write_bytes(b'Not a movie')
    try:
        module.measure(broken, 1)
        raise AssertionError('Invalid movie passed')
    except subprocess.CalledProcessError:
        pass
print('Silent video analysis passed: moving H.264, duration rejection, 1-s frozen tail, missing-frame gap and invalid file. No audio generated or measured.')
