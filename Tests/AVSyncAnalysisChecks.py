import importlib.util
import tempfile
import unittest
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('av_sync', root / 'scripts/check-av-sync.py')
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class AVSyncAnalysisChecks(unittest.TestCase):
    def test_limits_and_missing_pulses(self):
        flashes = [0.5 + 2 * i for i in range(12)]
        self.assertTrue(sync.compare(flashes, [value + 0.080 for value in flashes])['passed'])
        self.assertFalse(sync.compare(flashes, [value + 0.180 for value in flashes])['passed'])
        self.assertAlmostEqual(sync.compare(flashes, [value - 0.065 for value in flashes])['median_ms'], -65)
        with self.assertRaises(ValueError):
            sync.compare(flashes, flashes[:-1])
        with self.assertRaises(ValueError):
            sync.compare(flashes[:3], flashes[:3])

    def test_real_decoder_timestamps_and_inserted_offset(self):
        source = root / 'build/AVSyncFixture.app/Contents/Resources/AVSync.mp4'
        self.assertTrue(source.exists(), 'Run scripts/build-av-sync-fixture.sh first')
        reference = sync.measure(source, 0.100)
        self.assertTrue(reference['passed'])
        self.assertEqual(reference['optical_pulses'], 16)
        self.assertLess(reference['audio_tracks'][0]['max_absolute_ms'], 10)
        with tempfile.TemporaryDirectory(prefix='Snaprivo-AVSync-Analysis-') as folder:
            delayed = Path(folder) / 'Delayed.mp4'
            sync.run('ffmpeg', '-v', 'error', '-itsoffset', '0.18', '-i', str(source),
                '-i', str(source), '-map', '1:v:0', '-map', '0:a:0', '-c', 'copy', str(delayed))
            result = sync.measure(delayed, 0.100)
            self.assertFalse(result['passed'])
            self.assertGreater(result['audio_tracks'][0]['median_ms'], 150)
            self.assertLess(result['audio_tracks'][0]['median_ms'], 210)
            noisy = Path(folder) / 'With-Loud-Transient.mp4'
            sync.run('ffmpeg', '-v', 'error', '-i', str(source), '-f', 'lavfi',
                '-i', 'anoisesrc=sample_rate=48000:duration=32:amplitude=1:seed=42',
                '-filter_complex', "[1:a]volume='if(between(t,10.05,10.10),4,0)':eval=frame[n];[0:a][n]amix=inputs=2:normalize=0[a]",
                '-map', '0:v:0', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', str(noisy))
            result = sync.measure(noisy, 0.100)
            self.assertTrue(result['passed'], 'A loud broadband transient hid the quieter test tone')
            self.assertEqual(result['optical_pulses'], 16)


if __name__ == '__main__':
    unittest.main()
