"""Gate rejection proofs; no binary, CPU counters or app runtime used."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('collector', Path(__file__).with_name('collect.py'))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class BoundaryGateTests(unittest.TestCase):
    def test_floor_and_spread(self):
        samples = lambda *values: [{'cpu_idle_percent': value} for value in values]
        self.assertTrue(collector.idle_gate(samples(85, 95)))
        self.assertFalse(collector.idle_gate(samples(84.99, 90)))
        self.assertFalse(collector.idle_gate(samples(85, 95.01)))

    def test_before_rejection_launches_no_child(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'evidence'
            with patch.object(collector, 'write_fingerprint'), patch.object(collector, 'host_sample', side_effect=[{'cpu_idle_percent': 90}] * 5 + [{'cpu_idle_percent': 84}]), patch.object(collector.subprocess, 'check_output') as child:
                with self.assertRaisesRegex(RuntimeError, 'next workload not launched'):
                    collector.collect(output)
                child.assert_not_called()
            self.assertEqual(json.loads((output / 'rejection.json').read_text())['stage'], 'before')
            self.assertFalse((output / 'runs.json').exists())

    def test_after_rejection_preserves_row(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'evidence'
            def workload(args, **kwargs):
                scenario = args[args.index('--scenario') + 1]
                return json.dumps({'scenario': scenario, 'runs_ms': [1] * 20, 'checksum': 23000 * (999 if scenario == 'focused-selection' else .5)})
            with patch.object(collector, 'write_fingerprint'), patch.object(collector, 'host_sample', side_effect=[{'cpu_idle_percent': 90}] * 6 + [{'cpu_idle_percent': 84}]), patch.object(collector.subprocess, 'check_output', side_effect=workload):
                with self.assertRaisesRegex(RuntimeError, 'row preserved'):
                    collector.collect(output)
            self.assertEqual(len(json.loads((output / 'runs.json').read_text())), 1)
            self.assertEqual(json.loads((output / 'rejection.json').read_text())['stage'], 'after')
            self.assertFalse((output / 'summary.json').exists())


if __name__ == '__main__':
    unittest.main()
