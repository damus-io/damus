#!/usr/bin/env python3
"""Check NIP-808 target membership and Swift syntax; this is not an Apple SDK build.

Optional positional paths add changed Swift files to the voice production/test files.
No packages are installed and no user data, network services or git state are changed.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import shutil
import subprocess
import sys


def project_objects(text):
    starts = list(re.finditer(r'(?m)^\t\t([A-F0-9]{24})(?: /\* ([^\r\n]*?) \*/)? = \{', text))
    objects = {}
    for index, start in enumerate(starts):
        key = start.group(1)
        if key in objects:
            raise ValueError('Duplicate project object: ' + key)
        end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
        objects[key] = (start.group(2), text[start.end():end])
    return objects


def members(body, field):
    match = re.search(r'\b' + field + r' = \((.*?)\);', body, re.S)
    if not match:
        raise ValueError('Missing project list: ' + field)
    return re.findall(r'\b[A-F0-9]{24}\b', match.group(1))


def check_targets(repo, production, tests):
    objects = project_objects((repo / 'damus.xcodeproj/project.pbxproj').read_text(encoding='utf-8'))
    target_files = {}
    for label, body in objects.values():
        if not re.search(r'\bisa = PBXNativeTarget;', body):
            continue
        names = []
        for phase in members(body, 'buildPhases'):
            phase_body = objects[phase][1]
            if not re.search(r'\bisa = PBXSourcesBuildPhase;', phase_body):
                continue
            for build in members(phase_body, 'files'):
                reference = re.search(r'\bfileRef = ([A-F0-9]{24})', objects[build][1])
                if reference:
                    names.append(objects[reference.group(1)][0])
        target_files[label] = names
    for target in ['damus', 'ShareExtension', 'HighlighterActionExtension']:
        for path in production:
            if target_files[target].count(path.name) != 1:
                raise ValueError(f'{target}: {path.name} must appear exactly once')
    for path in tests:
        if target_files['damusTests'].count(path.name) != 1:
            raise ValueError('damusTests: missing/duplicate ' + path.name)
    for filename in ['NostrKind.swift', 'NdbNote.swift', 'LocalNotification.swift',
                     'NotificationFormatter.swift', 'NotificationService.swift', 'nostrdb.c']:
        if target_files['DamusNotificationService'].count(filename) != 1:
            raise ValueError('Notification extension: missing/duplicate ' + filename)
    for label, body in objects.values():
        if label not in {p.name for p in production + tests}:
            continue
        if 'isa = PBXFileReference;' not in body:
            continue
        match = re.search(r'\bpath = ([^;]+);', body)
        if not match or 'sourceTree = SOURCE_ROOT;' not in body:
            raise ValueError('Voice source reference must resolve from SOURCE_ROOT: ' + label)
        if not (repo / match.group(1).strip('"')).is_file():
            raise ValueError('Missing voice source: ' + label)
    print(f'PASS: {len(production)} voice sources in app/share/highlighter; {len(tests)} XCTest files; notification dependencies; unique project IDs', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swiftc', default=shutil.which('swiftc'))
    parser.add_argument('files', nargs='*')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    production = sorted((repo / 'damus/Features/Voice').rglob('*.swift'))
    tests = sorted((repo / 'damusTests').glob('Voice*Tests.swift'))
    if len(production) != 16 or len(tests) != 7:
        parser.error('Unexpected voice file inventory; review target expectations')
    check_targets(repo, production, tests)
    if not args.swiftc:
        parser.error('No swiftc available; target check passed, Swift syntax was NOT checked')
    subprocess.run([args.swiftc, '--version'], check=True)
    paths = sorted(set(production + tests + [repo / path for path in args.files]))
    def parse(path):
        return path, subprocess.run([args.swiftc, '-frontend', '-parse', str(path)],
                                    capture_output=True, text=True, timeout=120)
    failures = 0
    with ThreadPoolExecutor(max_workers=4) as workers:
        for path, result in workers.map(parse, paths):
            if result.stdout:
                print(result.stdout, end='')
            if result.stderr:
                print(result.stderr, end='')
            if result.returncode:
                failures += 1
                print('FAIL:', path.relative_to(repo), flush=True)
    if failures:
        raise SystemExit(f'{failures} Swift parse failures')
    print(f'PASS: Swift syntax parsed for {len(paths)} files; Apple type checking and runtime tests remain separate', flush=True)


if __name__ == '__main__':
    main()
