"""Compare admiral_audit2 logs. Usage: python -I adm2_cmp.py <dir> <tag1> <tag2> ... [--keys k1,k2]
Reads <dir>/<tag>_seed<N>.txt (AUDIT_JSON line), prints one row per metric
with the per-seed values and the mean for each tag. Metrics add both teams
unless the name ends in _T0/_T1."""
import json, sys, glob, re, os

def load(fn):
    L = [l for l in open(fn, encoding='utf8', errors='replace') if l.startswith('AUDIT_JSON ')]
    return json.loads(L[-1][11:]) if L else None

def both(d, k):
    return sum(float(d['counters'][t].get(k, 0.0)) for t in (0, 1))

def pushshare(d, pre, lane):
    tot = sum(both(d, pre + l) for l in ('top', 'mid', 'bot'))
    return 100.0 * both(d, pre + lane) / tot if tot else 0.0

def metrics(d):
    m = {}
    m['end_time'] = d['time']
    m['ended'] = 1 if d['phase'] != 'play' else 0
    m['samples'] = both(d, 'samples') / 2
    for k in ['siege_declared', 'siege_off_admiral', 'siege_off_defend', 'siege_s_gather', 'siege_s_assault',
              'assault_contact_s', 'siege_ready_s', 'siege_ready_blocked_def_s', 'defending_s', 'defending_away_s',
              'ms_moves', 'ms_away_s', 'ms_moving_s', 'bays_made', 'bay_died', 'ward_died', 'wards_made', 'drone_died', 'turrets_made',
              'turret_died_inner', 'turret_died_middle', 'cmd_turret_fail', 'cmd_drone_fail', 'cmd_drone_ok']:
        m[k] = both(d, k)
    m['ems_hull_lost'] = both(d, 'ems_hull_lost')
    m['ems_hull_lost_assault'] = both(d, 'ems_hull_lost_assault')
    sd = both(d, 'siege_declared')
    m['siege_dur_avg'] = both(d, 'siege_dur_sum') / max(1.0, both(d, 'siege_off'))
    sm = both(d, 'samples') / 2
    m['ms_gap_avg'] = both(d, 'ms_gap_sum') / max(1.0, both(d, 'samples'))
    m['bays_alive_avg'] = both(d, 'bays_sum') / max(1.0, both(d, 'samples'))
    m['bay_life_avg'] = both(d, 'bay_life_sum') / max(1.0, both(d, 'bay_died'))
    m['spent_bays'] = both(d, 'spent_bays')
    m['tre_avg'] = both(d, 'tre_sum') / max(1.0, both(d, 'samples'))
    m['tre_over5k_s'] = both(d, 'tre_over_5000_s')
    for l in ('top', 'mid', 'bot'):
        m['push_' + l + '%'] = pushshare(d, 'push_', l)
        m['fracfront_' + l + '%'] = pushshare(d, 'fracfront_', l)
        m['wp_' + l + '%'] = pushshare(d, 'wp_', l)
        m['pil_' + l + '%'] = pushshare(d, 'pil_', l)
        m['ms_lane_' + l + '%'] = pushshare(d, 'ms_lane_', l)
    m['push_ne_fracfront%'] = 100.0 * both(d, 'push_ne_fracfront') / max(1.0, both(d, 'samples'))
    m['end_ms_hull_T0'] = d['counters'][0].get('end_ms_hull', 0)
    m['end_ms_hull_T1'] = d['counters'][1].get('end_ms_hull', 0)
    m['winner'] = d.get('winner', -2)
    return m

def main():
    a = sys.argv[1:]
    keys = None
    if '--keys' in a:
        i = a.index('--keys'); keys = a[i + 1].split(','); a = a[:i] + a[i + 2:]
    d = a[0]; tags = a[1:]
    res = {}
    for tag in tags:
        res[tag] = {}
        for fn in sorted(glob.glob(os.path.join(d, tag + '_seed*.txt'))):
            mm = re.search(r'_seed(\d+)\.txt$', fn)
            if not mm: continue
            j = load(fn)
            if j: res[tag][int(mm.group(1))] = metrics(j)
    allm = []
    for tag in tags:
        for s, m in res[tag].items():
            for k in m:
                if k not in allm: allm.append(k)
    if keys: allm = [k for k in allm if k in keys]
    print('%-28s' % 'metric' + ''.join('%-34s' % t for t in tags))
    for k in allm:
        row = '%-28s' % k
        for t in tags:
            vals = [res[t][s].get(k, 0.0) for s in sorted(res[t])]
            if not vals: row += '%-34s' % '-'; continue
            mean = sum(vals) / len(vals)
            row += '%-34s' % ('%s | %.1f' % ('/'.join('%.0f' % v if abs(v) >= 10 else '%.2f' % v for v in vals), mean))
        print(row)

main()
