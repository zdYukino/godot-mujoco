#!/usr/bin/env python3
"""Fetch only the pinned official Linux .NET archive; verify before extraction."""
import hashlib
import json
import os
import pathlib
import platform
import sys
import urllib.request
import zipfile
import shutil


def file_hash(path, algorithm):
    value = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def install(destination, archive_dir=None):
    config = json.loads(pathlib.Path(__file__).with_name('toolchain.json').read_text())
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise RuntimeError('Only Linux x86_64 is supported')
    destination = pathlib.Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    cache = pathlib.Path(archive_dir).resolve() if archive_dir else destination
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / 'godot-mono.zip'
    if not archive.exists():
        temp = archive.with_suffix('.part')
        try:
            with urllib.request.urlopen(config['godot_url'], timeout=60) as source, temp.open('wb') as target:
                shutil.copyfileobj(source, target, 1024 * 1024)
            for algorithm in ('sha256', 'sha512'):
                if file_hash(temp, algorithm) != config['godot_archive_' + algorithm]:
                    raise RuntimeError('Godot archive checksum mismatch')
            temp.replace(archive)
        finally:
            temp.unlink(missing_ok=True)
    for algorithm in ('sha256', 'sha512'):
        if file_hash(archive, algorithm) != config['godot_archive_' + algorithm]:
            raise RuntimeError('Godot archive checksum mismatch; remove the invalid cache explicitly')
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            target = (destination / entry.filename).resolve()
            if not target.is_relative_to(destination):
                raise RuntimeError('Archive path escapes destination')
        package.extractall(destination)
        for entry in package.infolist():
            mode = entry.external_attr >> 16
            if mode & 0o111:
                os.chmod(destination / entry.filename, 0o755)
    binary = destination / config['godot_binary']
    if file_hash(binary, 'sha256') != config['godot_binary_sha256']:
        raise RuntimeError('Godot executable checksum mismatch')
    binary.chmod(0o755)
    return binary


if __name__ == '__main__':
    print(install(sys.argv[1]))
