"""Offline optimized pure-core baseline and profiles; no app/hardware adapters."""
import argparse
import hashlib
import json
import math
import os
import platform
import random
import re
import resource
import statistics
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

UTC = timezone.utc
ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / '.build/synthetic-profile'
SCENARIOS = ['focused-selection', 'luminance-core']


def host_sample():
    # n=0 prevents collection of other applications' process data.
    result = subprocess.run(
        ["/usr/bin/top", "-l", "2", "-s", "1", "-n", "0"], capture_output=True, text=True, check=True, timeout=10
    )
    lines = re.findall(r"CPU usage: ([\d.]+)% user, ([\d.]+)% sys, ([\d.]+)% idle", result.stdout)
    if not lines:
        raise RuntimeError("numeric macOS CPU sample unavailable")
    user, system, idle = map(float, lines[-1])
    return {
        "utc": datetime.now(UTC).isoformat(),
        "load": os.getloadavg(),
        "cpu_user_percent": user,
        "cpu_system_percent": system,
        "cpu_idle_percent": idle,
    }



def idle_gate(samples):
    idle = [row['cpu_idle_percent'] for row in samples]
    return min(idle) >= 85 and max(idle) - min(idle) <= 10


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def write_fingerprint(output):
    files = list((ROOT / 'Sources/BordersCore').glob('*.swift')) + [ROOT / 'Benchmarks/Synthetic/main.swift', ROOT / 'Benchmarks/Synthetic/collect.py', BINARY]
    fingerprint = {'utc': datetime.now(UTC).isoformat(), 'platform': platform.platform(),
        'source_sha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'swift': subprocess.check_output(['swiftc', '--version'], text=True).strip(),
        'hardware': subprocess.check_output(['sysctl', '-n', 'hw.model', 'hw.physicalcpu', 'hw.logicalcpu', 'hw.memsize'], text=True).splitlines(),
        'power': subprocess.check_output(['pmset', '-g', 'batt'], text=True).strip(),
        'filesystem': subprocess.check_output(['stat', '-f', '%T', str(ROOT)], text=True).strip(),
        'build': 'swiftc -O -g; symbols unstripped; no app runtime or hardware adapters',
        'source_sha256': {str(file.relative_to(ROOT)): hashlib.sha256(file.read_bytes()).hexdigest() for file in files}}
    (output / 'fingerprint.json').write_text(json.dumps(fingerprint, indent=2) + '\n')
    proof = subprocess.check_output([str(BINARY), '--check'], text=True)
    (output / 'golden.txt').write_text(proof)


def collect(output, allow_shared_host=False):
    output.mkdir(parents=True, exist_ok=False)
    write_fingerprint(output)
    preflight = [host_sample() for _ in range(5)]
    stable = idle_gate(preflight)
    (output / 'preflight.json').write_text(json.dumps({'samples': preflight, 'idle_gate_passed': stable, 'allow_shared_host': allow_shared_host}, indent=2) + '\n')
    if not stable and not allow_shared_host:
        raise RuntimeError('host idle gate failed; no workload timing collected')
    rng = random.Random(20261006)
    rows = []
    for phase, blocks in [('warmup', 3), ('measured', 20)]:
        for block in range(blocks):
            scenarios = SCENARIOS.copy()
            rng.shuffle(scenarios)
            for scenario in scenarios:
                before = host_sample()
                if not idle_gate([*preflight, before]) and not allow_shared_host:
                    (output / 'rejection.json').write_text(json.dumps({'sequence': len(rows), 'stage': 'before', 'sample': before}, indent=2) + '\n')
                    raise RuntimeError('host boundary idle gate failed; next workload not launched')
                usage = resource.getrusage(resource.RUSAGE_CHILDREN)
                start = time.perf_counter()
                result = json.loads(subprocess.check_output([str(BINARY), '--scenario', scenario], text=True, timeout=30))
                wall = time.perf_counter() - start
                after_usage = resource.getrusage(resource.RUSAGE_CHILDREN)
                cpu = after_usage.ru_utime + after_usage.ru_stime - usage.ru_utime - usage.ru_stime
                after = host_sample()
                assert result['scenario'] == scenario and len(result['runs_ms']) == 20
                assert abs(result['checksum'] - 23000 * (999 if scenario == 'focused-selection' else 0.5)) < 1e-8
                rows.append({'phase': phase, 'block': block, 'scenario': scenario, 'result': result, 'host_before': before, 'host_after': after, 'process_wall_seconds': wall, 'process_cpu_seconds': cpu, 'process_cpu_percent': cpu / wall * 100})
                (output / 'runs.json').write_text(json.dumps(rows, indent=2) + '\n')
                if not idle_gate([*preflight, before, after]) and not allow_shared_host:
                    (output / 'rejection.json').write_text(json.dumps({'sequence': len(rows) - 1, 'stage': 'after', 'sample': after}, indent=2) + '\n')
                    raise RuntimeError('host boundary idle gate failed; row preserved, collection rejected')
                print(f'{len(rows)}/46 {phase} {scenario}', flush=True)
    summary = {}
    for scenario in SCENARIOS:
        group = [row for row in rows if row['scenario'] == scenario and row['phase'] == 'measured']
        assert len(group) == 20
        medians = [statistics.median(row['result']['runs_ms']) for row in group]
        summary[scenario] = {'processes': 20, 'batches_per_process': 20, 'operations_per_batch': 1000,
            'batch_ms_median_of_process_medians': statistics.median(medians),
            'batch_ms_p95_median': statistics.median(percentile(row['result']['runs_ms'], .95) for row in group),
            'batch_ms_max': max(max(row['result']['runs_ms']) for row in group),
            'process_median_cv': statistics.stdev(medians) / statistics.mean(medians),
            'host_idle_min': min(row[key]['cpu_idle_percent'] for row in group for key in ['host_before', 'host_after']),
            'peak_rss_mib_median': statistics.median(row['result']['peak_rss_mib'] for row in group),
            'operations_per_second_median': statistics.median(1000000 / value for value in medians),
            'process_cpu_percent_median': statistics.median(row['process_cpu_percent'] for row in group)}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    profile_workloads(output)


def profile_workloads(output):
    for scenario in SCENARIOS:
        with (output / f'{scenario}-profile-proof.txt').open('w') as proof_file:
            child = subprocess.Popen([str(BINARY), '--scenario', scenario, '--profile-seconds', '15'], stdout=proof_file)
            try:
                sampled = subprocess.run(['/usr/bin/sample', str(child.pid), '10', '1', '-file', str(output / f'{scenario}.sample.txt')], capture_output=True, text=True, timeout=20)
                (output / f'{scenario}-sampler.json').write_text(json.dumps({'returncode': sampled.returncode, 'stdout': sampled.stdout, 'stderr': sampled.stderr}, indent=2) + '\n')
                assert sampled.returncode == 0
                assert child.wait(timeout=20) == 0
            finally:
                if child.poll() is None:
                    child.terminate()
                    child.wait(timeout=5)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--allow-shared-host', action='store_true')
    parser.add_argument('--profile-only', action='store_true', help='Only qualified source sampling; no timing baseline and no isolation claim')
    args = parser.parse_args()
    destination = args.output.resolve()
    if args.profile_only:
        destination.mkdir(parents=True, exist_ok=False)
        write_fingerprint(destination)
        before = host_sample()
        profile_workloads(destination)
        after = host_sample()
        (destination / 'profile-host.json').write_text(json.dumps({'before': before, 'after': after,
            'scope': 'source-only optimized synthetic child sampling; background load not controlled; no timing baseline'}, indent=2) + '\n')
    else:
        collect(destination, args.allow_shared_host)
