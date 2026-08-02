"""Cross-check the analytics catalog against every call site (features/analytics.md).

    python tools/headless-sim/catalog_xcheck.py

Two invariants, both of which fail SILENTLY at runtime if broken:

  * every event / flow-step / funnel-step key referenced anywhere in src/ must
    exist in AnalyticsConfig. A key that does not is a metric that never
    appears on the dashboard, with no error at the call site.
  * every key a CLIENT asserts must be on the trust allow-list
    (clientFlowSteps / clientFunnels), or Ingest refuses it — the beat is
    written, sent, and dropped, and nothing says so except one warn.

It has already caught both: an undefined variable in an event's field list,
and three matchmaking funnel steps the client sends that a tightened
allow-list had started refusing.
"""
import re, io, glob, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")) + "/"
cfg = io.open(ROOT + 'src/shared/config/AnalyticsConfig.lua', encoding='utf-8').read()

events = set(re.findall(r'\["([a-z0-9\-]+)"\]\s*=\s*"[a-z0-9_]+"',
                        cfg.split('AnalyticsConfig.events = {')[1].split('\n}')[0]))
flow = [m for m in re.findall(r'\{\s*key\s*=\s*"([a-z0-9\-]+)"',
                              cfg.split('AnalyticsConfig.flowSteps = {')[1].split('\n}')[0])]
flowset = set(flow)

funnels_block = cfg.split('AnalyticsConfig.funnels = {')[1].split('\n-- `flow` shares')[0]
funnels, cur = {}, None
for line in funnels_block.split('\n'):
    m = re.match(r'\t(\w+) = \{', line)
    if m:
        cur = m.group(1); funnels[cur] = set()
    found = re.findall(r'\{ key = "([a-z0-9\-]+)"', line)
    if cur and found:
        funnels[cur].update(found)
funnels['flow'] = flowset

# client allow-lists
cfs = set(re.findall(r'\["([a-z0-9\-]+)"\] = true', cfg.split('AnalyticsConfig.clientFlowSteps = {')[1].split('\n}')[0]))
cf_block = cfg.split('AnalyticsConfig.clientFunnels = {')[1].split('\n}')[0]
clientfunnels = {}
for line in cf_block.split('\n'):
    m = re.match(r'\t(\w+) = \{(.*)\},', line)
    if m:
        clientfunnels[m.group(1)] = set(re.findall(r'(\w+) = true', m.group(2)))

bad = []
for key in cfs:
    if key not in flowset:
        bad.append(('AnalyticsConfig', 'clientFlowSteps->flow', key))
for fn, steps in clientfunnels.items():
    if fn not in funnels:
        bad.append(('AnalyticsConfig', 'clientFunnels->funnel', fn)); continue
    for s in steps:
        if s not in funnels[fn]:
            bad.append(('AnalyticsConfig', f'clientFunnels[{fn}]->step', s))

for path in glob.glob(ROOT + 'src/**/*.lua', recursive=True):
    src = io.open(path, encoding='utf-8').read()
    rel = path.replace(ROOT, '')
    for m in re.finditer(r'\.Event\(\s*\w+\s*,\s*"([a-z0-9\-]+)"', src):
        if m.group(1) not in events: bad.append((rel, 'event', m.group(1)))
    for m in re.finditer(r'Sink\.Custom\(\s*\w+\s*,\s*"([a-z0-9\-]+)"', src):
        if m.group(1) not in events: bad.append((rel, 'event', m.group(1)))
    for m in re.finditer(r'\.Flow\(\s*\w+\s*,\s*"([a-z0-9\-]+)"', src):
        if m.group(1) not in flowset: bad.append((rel, 'flow', m.group(1)))
    for m in re.finditer(r'\.Funnel\(\s*\w+\s*,\s*"(\w+)"\s*,\s*"([a-z0-9\-]+)"', src):
        f, s = m.group(1), m.group(2)
        if f not in funnels: bad.append((rel, 'funnel-name', f))
        elif s not in funnels[f]: bad.append((rel, f'funnel:{f}', s))
    for m in re.finditer(r'\.Funnel\(\s*"(\w+)"\s*,\s*"([a-z0-9\-]+)"', src):
        f, s = m.group(1), m.group(2)
        if f not in funnels: bad.append((rel, 'funnel-name', f))
        elif s not in funnels[f]: bad.append((rel, f'funnel:{f}', s))
        # client-side call: must also be in the client allow-list
        elif f in funnels and s not in clientfunnels.get(f, set()):
            bad.append((rel, f'CLIENT-not-allowed:{f}', s))
    for m in re.finditer(r'\.BeginVisit\(\s*\w+\s*,\s*"(\w+)"', src):
        if m.group(1) not in funnels: bad.append((rel, 'visit-funnel', m.group(1)))
    # client Flow() calls must be in clientFlowSteps
    for m in re.finditer(r'Analytics\.Flow\(\s*"([a-z0-9\-]+)"', src):
        if m.group(1) not in cfs: bad.append((rel, 'CLIENT-flow-not-allowed', m.group(1)))

print("catalog:", len(events), "events,", len(funnels), "funnels,", len(flow), "flow steps")
print("client may assert:", len(cfs), "flow steps,", {k: len(v) for k, v in clientfunnels.items()})
if bad:
    print("\nMISMATCHES:")
    for b in bad: print("  ", b)
else:
    print("\nOK — every referenced key exists AND every client-side assertion is allow-listed.")
