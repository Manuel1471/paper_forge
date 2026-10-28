#!/usr/bin/env python3
"""Sequential Core-only campaign. No engine changes, commits, or network calls."""
import csv, datetime, hashlib, json, os, pathlib, platform, re, statistics, subprocess, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
STAMP = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
OUT = ROOT / 'benchmarks' / 'results' / STAMP
OUT.mkdir(parents=True, exist_ok=False)
RAW = OUT / 'raw'
RAW.mkdir()
ENV = dict(os.environ, MIX_ENV='prod')
ENV.pop('ERL_FLAGS', None)
ROWS = {'concurrency': [], 'schedulers': [], 'sustained': [], 'latency': []}

def command(args, env=None):
    return subprocess.run(args, cwd=ROOT, env=env or ENV, text=True, capture_output=True).stdout.strip()

def write_csv(name, rows):
    if not rows:
        return
    keys = list(dict.fromkeys(k for row in rows for k in row))
    with (OUT / (name + '.csv')).open('w', newline='') as f:
        writer = csv.DictWriter(f, keys)
        writer.writeheader()
        writer.writerows(rows)

def pressure():
    raw = command(['memory_pressure'])
    match = re.search(r'free percentage: (\d+)%', raw)
    return int(match[1]) if match else None

def core_hash():
    h = hashlib.sha256()
    for p in sorted((ROOT / 'lib').rglob('*.ex')):
        h.update(str(p.relative_to(ROOT)).encode())
        h.update(p.read_bytes())
    return h.hexdigest()

FROZEN = core_hash()
info = {
    'utc': STAMP, 'commit': command(['git', 'rev-parse', 'HEAD']), 'core_tree_sha256': FROZEN,
    'git_status': command(['git', 'status', '--short']),
    'hardware': command(['sysctl', 'machdep.cpu.brand_string', 'hw.memsize', 'hw.physicalcpu',
                        'hw.logicalcpu', 'hw.perflevel0.physicalcpu', 'hw.perflevel1.physicalcpu']),
    'os': command(['sw_vers']), 'architecture': platform.machine(),
    'elixir': command(['elixir', '--version']), 'mix': command(['mix', '--version']),
    'vm': command(['mix', 'run', '--no-compile', '-e',
                  'IO.inspect(%{schedulers: System.schedulers(), online: System.schedulers_online(), available: :erlang.system_info(:logical_processors_available), version: Mix.Project.config()[:version], mix_env: Mix.env()})']),
    'environment': {k: ENV.get(k) for k in ['MIX_ENV', 'ERL_FLAGS', 'ELIXIR_ERL_OPTIONS', 'MIX_TARGET', 'LANG']},
    'thermal_initial': command(['pmset', '-g', 'therm']), 'memory_free_percent_initial': pressure(),
}
(OUT / 'environment.md').write_text('# Verified benchmark environment\n\n```json\n' + json.dumps(info, indent=2) + '\n```\n\nThe working tree includes the reviewed 1.2/1.3 fixes. The commit alone does not identify it; use the archived patch and Core tree digest. No engine edits are allowed after this snapshot.\n')
(OUT / 'core-working-tree.patch').write_text(command(['git', 'diff', '--', 'lib', 'priv']))
for p in [ROOT / 'benchmarks/render_profiles.exs', ROOT / 'benchmarks/concurrent_renders.exs', ROOT / 'benchmarks/support/core_probe.exs', pathlib.Path(__file__)]:
    (RAW / p.name).write_bytes(p.read_bytes())


def cpu_seconds(value):
    bits = value.split(':')
    return sum(float(v) * 60 ** i for i, v in enumerate(reversed(bits)))


def run(kind, name, overrides, runner):
    assert core_hash() == FROZEN, 'Core changed during measurement'
    free = pressure()
    if free is not None and free < 15:
        row = dict(name=name, status='skipped_memory_pressure', free_percent=free)
        ROWS[kind].append(row); write_csv(kind, ROWS[kind])
        print(json.dumps(row), flush=True)
        return None
    output = RAW / (name + '.jsonl')
    reference = RAW / (name + '.pdf')
    env = dict(ENV, RESULT_JSONL=str(output), **overrides)
    if kind in ['concurrency', 'schedulers']:
        # Keep one reference per workload/mode; never all outputs.
        reference = RAW / (overrides['WORKLOAD'] + '-' + overrides.get('REFERENCE_PROFILE', 'false') + '.pdf')
        if not reference.exists(): env['REFERENCE_PDF'] = str(reference)
    cmd = ['mix', 'run', '--no-compile', runner]
    with (OUT / 'commands.jsonl').open('a') as f:
        f.write(json.dumps(dict(name=name, command=cmd, environment={k: env[k] for k in ['MIX_ENV','RESULT_JSONL'] + list(overrides)}, utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))+'\n')
    print(json.dumps(dict(event='start', name=name, free_percent=free)), flush=True)
    started = time.monotonic()
    samples = []
    stop_reason = None
    last_pressure = started
    with (RAW / (name + '.log')).open('w') as log, (RAW / (name + '-os.jsonl')).open('w') as telemetry:
        proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        prior_cpu = None
        while proc.poll() is None:
            now = time.monotonic()
            line = command(['ps', '-p', str(proc.pid), '-o', 'time=', '-o', 'rss=', '-o', '%cpu='])
            fields = line.split()
            if len(fields) == 3:
                cpu = cpu_seconds(fields[0]); rss = int(fields[1]) * 1024
                interval_cpu = None if prior_cpu is None else max(0, (cpu-prior_cpu[1])/(now-prior_cpu[0])*100)
                prior_cpu = (now,cpu)
                sample = dict(elapsed_seconds=now-started, cpu_seconds=cpu, cpu_percent=interval_cpu, rss_bytes=rss)
                samples.append(sample); telemetry.write(json.dumps(sample)+'\n'); telemetry.flush()
                if rss > 8_000_000_000: stop_reason = 'RSS exceeded 8 GB guard'
            if now-last_pressure >= 10:
                free = pressure(); last_pressure=now
                telemetry.write(json.dumps(dict(elapsed_seconds=now-started, free_percent=free))+'\n')
                if free is not None and free < 10: stop_reason = 'system memory free percentage below 10%'
            if stop_reason:
                proc.terminate()
                try: proc.wait(timeout=10)
                except subprocess.TimeoutExpired: proc.kill(); proc.wait()
                break
            time.sleep(1)
        returncode = proc.wait()
    events = []
    if output.exists():
        for line in output.read_text().splitlines():
            try: events.append(json.loads(line))
            except json.JSONDecodeError: pass
    os_metrics = dict(rss_peak_bytes=max([s['rss_bytes'] for s in samples] or [0]),
                      cpu_peak_percent=max([s['cpu_percent'] for s in samples if s['cpu_percent'] is not None] or [0]),
                      cpu_mean_percent=statistics.mean([s['cpu_percent'] for s in samples if s['cpu_percent'] is not None] or [0]),
                      process_elapsed_seconds=time.monotonic()-started)
    summaries = [e for e in events if e['event'] in ['concurrency_summary','latency_summary']]
    for e in summaries:
        if e['event'] == 'latency_summary':
            row = dict(name=name, profile=e['profile'], pages=e['pages'], pdf_bytes=e['pdf_bytes'], samples=e['samples'], warmups=e['warmups'])
            for k,v in e.items():
                if isinstance(v,dict) and 'median' in v:
                    row.update({k+'_'+m:n for m,n in v.items()})
        else:
            row = {k:v for k,v in e.items() if not isinstance(v,dict)}
            row.update(e['runtime']); row.update(name=name)
        row.update(os_metrics); row.update(status='ok' if returncode == 0 else 'failed', returncode=returncode, stop_reason=stop_reason)
        ROWS[kind].append(row)
    if not summaries:
        ROWS[kind].append(dict(name=name,status='failed',returncode=returncode,stop_reason=stop_reason,**os_metrics))
    write_csv(kind,ROWS[kind])
    if kind == 'sustained':
        intervals=[]
        start_event = next((e for e in events if e['event']=='measurement_start'),None)
        # OS series begins at process launch; match measurement start using first BEAM sample
        # timing is retained raw; process warmup is excluded from Core interval throughput.
        for e in events:
            if e['event']=='interval': intervals.append(dict(name=name,**e))
        with (OUT/'sustained_intervals.jsonl').open('a') as f:
            for e in intervals: f.write(json.dumps(e)+'\n')
    print(json.dumps(dict(event='done',name=name,returncode=returncode,summary=ROWS[kind][-1])),flush=True)
    (RAW/(name+'-thermal.txt')).write_text(command(['pmset','-g','therm']))
    time.sleep(10)
    return ROWS[kind][-1]

# Latency: historical runner retained, single-PDF timing additionally reported.
run('latency','latency',dict(SAMPLES='100',WARMUPS='10'), 'benchmarks/render_profiles.exs')
# Complete workload matrix, 3 repetitions, no simultaneous benchmark processes.
for repeat in range(1,4):
    for workload,jobs,levels in [('minimal',100000,[1,2,4,8,10,16]),('small',10000,[1,2,4,8,10,16]),('medium',10000,[1,2,4,8,10,16]),('large',200,[1,2,4,8,10])]:
        for c in levels:
            run('concurrency',f'{workload}-c{c}-r{repeat}',dict(WORKLOAD=workload,JOBS=str(jobs),CONCURRENCY=str(c),WARMUPS='10',REFERENCE_PROFILE='true'), 'benchmarks/concurrent_renders.exs')
# Distinct scheduler settings, including explicit 10 and default, 3 repeats.
for repeat in range(1,4):
    for schedulers in [2,4,6,8,10,None]:
        for c in [1,2,4,8,10]:
            opts=dict(WORKLOAD='medium',JOBS='10000',CONCURRENCY=str(c),WARMUPS='10',REFERENCE_PROFILE='true')
            if schedulers: opts['ERL_FLAGS']=f'+S {schedulers}:{schedulers}'
            run('schedulers',f's{ schedulers or "default" }-c{c}-r{repeat}',opts,'benchmarks/concurrent_renders.exs')
# Choose concurrency by median completed throughput, not a single lucky sample.
for workload,seconds in [('small',600),('medium',900),('large',300)]:
    groups={}
    for r in ROWS['concurrency']:
        if r.get('workload')==workload and r.get('status')=='ok' and not r.get('failures'):
            groups.setdefault(r['concurrency'],[]).append(r['renders_per_second'])
    if not groups: continue
    best=max(groups,key=lambda c:statistics.median(groups[c]))
    if workload=='large': best=max(groups)
    run('sustained',f'{workload}-sustained-c{best}',dict(WORKLOAD=workload,JOBS='1',CONCURRENCY=str(best),WARMUPS='10',REFERENCE_PROFILE='true',DURATION_SECONDS=str(seconds)),'benchmarks/concurrent_renders.exs')
assert core_hash()==FROZEN
(OUT/'complete.json').write_text(json.dumps(dict(finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),core_tree_sha256=FROZEN)))
print(json.dumps(dict(event='campaign_complete',output=str(OUT))),flush=True)
