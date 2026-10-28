#!/usr/bin/env python3
"""Summarize a campaign directory without changing or rerunning measurements."""
import csv, json, pathlib, statistics, sys
out=pathlib.Path(sys.argv[1]).resolve()

def rows(name):
    p=out/(name+'.csv')
    if not p.exists(): return []
    return list(csv.DictReader(p.open()))
def num(r,k):
    try:return float(r.get(k) or 0)
    except ValueError:return 0

def write(name,items):
    if not items:return
    keys=list(dict.fromkeys(k for r in items for k in r))
    with (out/(name+'.csv')).open('w',newline='') as f:
        w=csv.DictWriter(f,keys);w.writeheader();w.writerows(items)

concurrency=rows('concurrency'); schedulers=rows('schedulers'); latency=rows('latency')
completed=[r for r in concurrency if r.get('status')=='ok' and num(r,'failures')==0]
for collection in [concurrency,schedulers]:
    for r in collection:
        base=[num(x,'renders_per_second') for x in collection if x.get('workload')==r.get('workload') and x.get('schedulers')==r.get('schedulers') and x.get('concurrency')=='1' and x.get('status')=='ok']
        if base:r['throughput_relative_to_one_worker']=num(r,'renders_per_second')/statistics.median(base)
write('concurrency',concurrency);write('schedulers',schedulers)
# Preserve summary separately, expose requested 10-second interval table.
summary_path=out/'sustained_summary.csv'
sustained=rows('sustained_summary') if summary_path.exists() else rows('sustained')
if sustained:write('sustained_summary',sustained)
intervals=[]
p=out/'sustained_intervals.jsonl'
if p.exists():
    for line in p.read_text().splitlines():
        e=json.loads(line);name=e['name']
        summary=next((r for r in sustained if r['name']==name),{})
        samples=[json.loads(l) for l in (out/'raw'/(name+'-os.jsonl')).read_text().splitlines()]
        # Process timing includes warmup and exit; estimate offset, at most one polling interval of uncertainty.
        offset=num(summary,'process_elapsed_seconds')-num(summary,'elapsed_ms')/1000
        end=offset+e['elapsed_seconds'];start=end-e['seconds']
        selected=[s for s in samples if start<=s['elapsed_seconds']<=end and 'rss_bytes' in s]
        cpus=[s['cpu_percent'] for s in selected if s.get('cpu_percent') is not None]
        e.update(cpu_mean_percent=statistics.mean(cpus) if cpus else None,cpu_peak_percent=max(cpus) if cpus else None,
                 rss_peak_bytes=max([s['rss_bytes'] for s in selected] or [0]),os_alignment_uncertainty_seconds=1.1)
        intervals.append(e)
if intervals:write('sustained',intervals)
status='COMPLETE' if (out/'complete.json').exists() else 'IN PROGRESS — partial results'
text=['# PaperForge Core benchmark report', '',status,'',
'## Scope and reproducibility','',
'Core PDF generation only. No Phoenix, databases, network, storage service or platform simulation. See `environment.md`, `commands.jsonl`, the Core patch/digest and archived runner sources. Measurements use `MIX_ENV=prod` and `--no-compile`; warmups precede every series. No Core changes or commits are made during the campaign.', '',
'## Reference documents','',
'Latency and the main concurrent campaign use the same unchanged reference document: Small 25 rows/2 pages, Medium 500/18, Large 5000/179. The legacy concurrent mode remains available but omits two paragraphs; its Small output is 1 page. Minimal retains its original one-page indexed text. Consequently historical concurrent results are contextual, not an equivalent controlled comparison.', '',
'Each reference is parsed before timing. Every generated reference-profile PDF is checked against its deterministic reference SHA-256, envelope and page count. Only the reference PDFs are retained. Minimal outputs vary by index; their ordered aggregate digest should match across repetitions and concurrency levels.', '',
'## Individual latency','',
'`single_render_ms` = layout + first serialization. Historical `total_ms` additionally includes a second warm serialization, retained for compatibility. Preparation is separately timed. Process peak memory is sampled and may miss brief peaks; GC counts in this runner are VM-wide, not per-process. CPU/RSS summaries encompass process launch and warmups, whereas Core timers exclude them.', '',
'| Profile | Pages | Bytes | Single PDF median ms | p95 ms | p99 ms | Historical total median ms |',
'|---|---:|---:|---:|---:|---:|---:|']
for r in latency:
    if r.get('status')=='ok':text.append(f"| {r['profile']} | {r['pages']} | {r['pdf_bytes']} | {num(r,'single_render_ms_median'):.2f} | {num(r,'single_render_ms_p95'):.2f} | {num(r,'single_render_ms_p99'):.2f} | {num(r,'total_ms_median'):.2f} |")
text+=['','## Throughput and concurrency','','The maximum is the best individual completed run. The recommended concurrency maximizes the median of repeated runs; it is workload- and machine-specific. Throughput includes bounded job scheduling, validation and lightweight JSONL instrumentation. Per-job `engine_us` separately times rendering, while job latency includes validation. No binary PDFs are retained in result collections.','','| Profile | Max PDF/s | Best median workers | Median PDF/s | Max observed PDF/hour | Max observed PDF/24h | Peak RSS MiB | Peak BEAM MiB |','|---|---:|---:|---:|---:|---:|---:|---:|']
for workload in ['minimal','small','medium','large']:
    subset=[r for r in completed if r['workload']==workload]
    if not subset:continue
    groups={}
    for r in subset:groups.setdefault(r['concurrency'],[]).append(num(r,'renders_per_second'))
    best=max(groups,key=lambda c:statistics.median(groups[c]));maximum=max(num(r,'renders_per_second') for r in subset)
    text.append(f"| {workload} | {maximum:.2f} | {best} | {statistics.median(groups[best]):.2f} | {maximum*3600:,.0f} | {maximum*86400:,.0f} | {max(num(r,'rss_peak_bytes') for r in subset)/2**20:.1f} | {max(num(r,'peak_beam_memory_bytes') for r in subset)/2**20:.1f} |")
text+=['','## Sustained throughput','','| Profile | Workers | PDF/s | First third PDF/s | Last third PDF/s | Change | Failures |','|---|---:|---:|---:|---:|---:|---:|']
for r in sustained:
    values=[e['pdf_per_second'] for e in intervals if e['name']==r['name']]
    if not values:continue
    n=max(1,len(values)//3);first=statistics.mean(values[:n]);last=statistics.mean(values[-n:])
    text.append(f"| {r['workload']} | {r['concurrency']} | {num(r,'renders_per_second'):.2f} | {first:.2f} | {last:.2f} | {(last/first-1)*100:+.1f}% | {r['failures']} |")
text+=['','## Scheduler scaling','','`schedulers.csv` records actual schedulers inside each VM. Limiting BEAM schedulers does not pin processes to cores or emulate a VPS/vCPU allocation. Apple performance and efficiency cores are heterogeneous. CPU 100% means one logical CPU; values can exceed 100%. RSS is OS resident memory; BEAM totals include allocator/accounting differences and are not interchangeable.','','| Schedulers | Workers | Median PDF/s | PDF/s per scheduler | Runs |','|---|---:|---:|---:|---:|']
groups={}
for r in schedulers:
    if r.get('status')=='ok':groups.setdefault((r['name'].split('-')[0],r['schedulers'],r['concurrency']),[]).append(num(r,'renders_per_second'))
for (label,s,c),values in groups.items():text.append(f'| {label} ({s} effective) | {c} | {statistics.median(values):.2f} | {statistics.median(values)/int(s):.2f} | {len(values)} |')
text+=['','## Comparison with 1.4.4','','Supplied historical medians: Small 1.90 ms, Medium 39.13 ms, Large 824.77 ms. Historical Medium throughput: 24.52 / 45.11 / 89.93 / 122.80 PDF/s at 1 / 2 / 5 / 10 workers; Large: 2.12 / 4.99 at 2 / 10 workers. The old raw results, exact timing boundary and frozen source are not supplied. Current reference-profile concurrency has extra content relative to the old concurrent runner, and instrumentation differs. Do not attribute numerical differences to engine changes.','','## Limits and interpretation','','- Capacity/hour and /24h are arithmetic extrapolations from observed throughput, not measured daily production capacity or VPS predictions. Real service limits, contention, throttling and external work are excluded.','- No thermal sensor or power telemetry is assumed available. Raw `pmset -g therm` reports are retained. Absence of an OS warning cannot establish absence of thermal throttling. Ten-second cooldowns and recorded repeat order reduce, but do not eliminate, thermal/order effects.','- The host is not dedicated; editor and OS activity can affect timings. Memory guards stop a configuration above 8 GB RSS or below 10% system free-memory indicator, and skip starting below 15%. This indicator is not a precise measurement of allocatable RAM.','- OS CPU/RSS sampling is approximately 1 second; BEAM sampling is 200 ms. Peaks below those intervals may be missed. Sustained interval OS alignment has about 1.1 seconds of uncertainty; PDF interval counters are exact.','- Per-process peak memory from the existing concurrency wrapper can be zero for short jobs that finish before its first sample; zero does not mean zero allocation.','- Layout vs serialization timings help identify expensive stages; concurrency/GC trends suggest contention but cannot prove a specific bottleneck without a profiler. No optimizations are performed during measurement.','- Structural parsing and deterministic-byte checks do not replace independent visual verification or formal PDF conformance certification.','','## Completion and failures','']
for name,rs in [('concurrency',concurrency),('schedulers',schedulers),('sustained',sustained)]:
    text.append(f'- {name}: {sum(r.get("status")=="ok" for r in rs)} completed configurations; {sum(r.get("status")!="ok" for r in rs)} failed/skipped.')
if status.startswith('IN PROGRESS'):text.append('\nThis report is provisional. Missing matrix cells and sustained runs are not results and must not be treated as zero or successful.')
(out/'benchmark_report.md').write_text('\n'.join(text)+'\n')
print(out/'benchmark_report.md')
