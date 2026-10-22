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


def install(destination):
    config = json.loads(pathlib.Path(__file__).with_name('toolchain.json').read_text())
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise RuntimeError('Only Linux x86_64 is supported')
    destination = pathlib.Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / 'godot-mono.zip'
    if not archive.exists():
        temp = archive.with_suffix('.part')
        urllib.request.urlretrieve(config['godot_url'], temp)
        temp.replace(archive)
    data = archive.read_bytes()
    for algorithm in ('sha256', 'sha512'):
        if hashlib.new(algorithm, data).hexdigest() != config['godot_archive_' + algorithm]:
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
    if hashlib.sha256(binary.read_bytes()).hexdigest() != config['godot_binary_sha256']:
        raise RuntimeError('Godot executable checksum mismatch')
    binary.chmod(0o755)
    print(binary)


if __name__ == '__main__':
    install(sys.argv[1])
