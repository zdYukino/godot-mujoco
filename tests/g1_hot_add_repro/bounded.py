#!/usr/bin/env python3
"""Linux-only bounded monitor. Signals only the process group it creates."""
import argparse
import ctypes
import json
import os
import pathlib
import signal
import subprocess
import time


def available():
    return int(next(x.split()[1] for x in pathlib.Path('/proc/meminfo').read_text().splitlines()
                    if x.startswith('MemAvailable:')))


def cgroup_snapshot():
    result = {}
    try:
        rel = next(x.split(':', 2)[2] for x in pathlib.Path('/proc/self/cgroup').read_text().splitlines()
                   if x.startswith('0::'))
        base = pathlib.Path('/sys/fs/cgroup') / rel.lstrip('/')
        for name in ['memory.current', 'memory.events', 'memory.pressure', 'io.pressure', 'cpu.pressure']:
            try:
                result[str(base / name)] = (base / name).read_text()
            except OSError as e:
                result[str(base / name)] = str(e)
    except (OSError, StopIteration) as e:
        result['unavailable'] = str(e)
    return result


def group_members(pgid):
    members = {}
    for entry in pathlib.Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            fields = (entry / 'stat').read_text().rsplit(')', 1)[1].split()
            if int(fields[2]) == pgid and int(fields[3]) == pgid:
                members[int(entry.name)] = fields[0]
        except (FileNotFoundError, ProcessLookupError):
            pass  # Process exited during enumeration.
    return members


def cleanup(child):
    # Leader remains unreaped (waitid WNOWAIT below), pinning its PID/PGID until
    # all signals have been sent. Do not use poll()/wait() before this boundary.
    pgid = child.pid
    report = {'pgid': pgid, 'signals': [], 'remaining': {}, 'errors': []}
    for sig, grace in [(signal.SIGTERM, 3), (signal.SIGKILL, 3)]:
        try:
            os.killpg(pgid, sig)
            report['signals'].append(signal.Signals(sig).name)
        except ProcessLookupError:
            break
        except OSError as e:
            report['errors'].append(repr(e))
            break
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            try:
                if not any(state != 'Z' for state in group_members(pgid).values()):
                    break
            except Exception as e:
                report['errors'].append(repr(e))
                break  # Still escalate to KILL; cannot claim verified cleanup.
            time.sleep(.05)
        else:
            continue
        if not report['errors']:
            break
    try:
        child.wait(timeout=1)
    except subprocess.TimeoutExpired:
        report['errors'].append('leader did not exit after SIGKILL')
    # Subreaper adopts orphaned descendants; reap only children in our group.
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        try:
            pid, _ = os.waitpid(-pgid, os.WNOHANG)
            if pid:
                continue
        except ChildProcessError:
            break
        time.sleep(.02)
    try:
        report['remaining'] = group_members(pgid)
    except Exception as e:
        report['errors'].append(repr(e))
    return report


def main(argv=None, memory_sample=available):
    p = argparse.ArgumentParser()
    p.add_argument('--log', type=pathlib.Path, required=True)
    p.add_argument('--seconds', type=float, default=45)
    p.add_argument('--min-available-mib', type=int, default=400)
    p.add_argument('--max-rss-mib', type=int, default=1800)
    p.add_argument('command', nargs=argparse.REMAINDER)
    a = p.parse_args(argv)
    cmd = a.command[1:] if a.command[:1] == ['--'] else a.command
    if not cmd:
        p.error('command required')
    if a.log.exists() or a.log.with_suffix('.resources.json').exists():
        p.error('Use new log/report paths; existing evidence is never overwritten')
    low = memory_sample()
    if low < 768 * 1024:
        raise SystemExit('Not started: less than 768 MiB available')
    # Monitor-local Linux setting, not a global/system change. Fail before
    # spawning if adoption/reaping cannot be enabled.
    if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), 'PR_SET_CHILD_SUBREAPER failed; no child started')
    interrupted = []
    old_handlers = {}
    for sig in (signal.SIGINT, signal.SIGTERM):
        old_handlers[sig] = signal.signal(sig, lambda number, _frame: interrupted.append(number))
    start = time.monotonic()
    peak = 0
    samples = []
    last_sample = -5
    child = None
    log_created = False
    reason = 'completed'
    error = None
    cleaning = {}
    cg_before = cgroup_snapshot()
    try:
        with a.log.open('x') as log:
            log_created = True
            child = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            while os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is None:
                if interrupted:
                    reason = 'monitor_interrupted'
                    break
                low = min(low, memory_sample())
                try:
                    status = pathlib.Path(f'/proc/{child.pid}/status').read_text()
                    rss = int(next(x.split()[1] for x in status.splitlines() if x.startswith('VmRSS:')))
                    peak = max(peak, rss)
                except (FileNotFoundError, StopIteration):
                    pass
                elapsed = time.monotonic() - start
                if elapsed - last_sample >= 5:
                    row = {'elapsed': elapsed, 'threads': {}}
                    try:
                        for task in pathlib.Path(f'/proc/{child.pid}/task').iterdir():
                            try:
                                fields = (task / 'stat').read_text().rsplit(')', 1)[1].split()
                                row['threads'][task.name] = {
                                    'state': fields[0], 'utime_ticks': int(fields[11]),
                                    'stime_ticks': int(fields[12]), 'wchan': (task / 'wchan').read_text().strip()}
                            except FileNotFoundError:
                                pass
                    except FileNotFoundError:
                        pass
                    samples.append(row)
                    last_sample = elapsed
                if elapsed >= a.seconds:
                    reason = 'timeout'
                elif low < a.min_available_mib * 1024:
                    reason = 'low_available_memory'
                elif peak > a.max_rss_mib * 1024:
                    reason = 'rss_limit'
                if reason != 'completed':
                    break
                time.sleep(.1)
    except BaseException as e:
        reason = 'monitor_interrupted' if isinstance(e, KeyboardInterrupt) else 'monitor_exception'
        error = repr(e)
    finally:
        # Repeated INT/TERM cannot abort bounded cleanup. SIGKILL of this monitor
        # is inherently uncatchable and is outside this guarantee.
        try:
            if child is not None:
                cleaning = cleanup(child)
        finally:
            for sig, handler in old_handlers.items():
                signal.signal(sig, handler)
    if not log_created:
        print('Monitor did not start: ' + str(error))
        return 1
    if interrupted and reason == 'completed':
        reason = 'monitor_interrupted'
    result = {'command': cmd, 'elapsed_seconds': time.monotonic() - start,
              'exit': child.returncode if child else None, 'reason': reason, 'error': error,
              'peak_sampled_rss_kib': peak, 'lowest_available_kib': low,
              'cpu_thread_samples': samples, 'cgroup_before': cg_before,
              'cgroup_after': cgroup_snapshot(), 'cleanup': cleaning,
              'loader_environment': {key: os.environ.get(key) for key in ['LD_LIBRARY_PATH', 'LD_PRELOAD']}}
    a.log.with_suffix('.resources.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items()
                      if k not in ['cpu_thread_samples', 'cgroup_before', 'cgroup_after']}))
    return 0 if result['exit'] == 0 and reason == 'completed' and not cleaning.get('remaining') and not cleaning.get('errors') else 1


if __name__ == '__main__':
    raise SystemExit(main())
