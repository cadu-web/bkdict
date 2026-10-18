#!/usr/bin/env python3
"""Gera windows/Bkdict/Assets/AppIcon.ico (16 a 256 px, quadros PNG) a partir de Resources/AppIcon-windows-1024.png.

Faz no Mac o mesmo que o build.ps1 faz no Windows, para o scripts/release.sh compilar a versão Windows daqui.
Usa o sips do macOS para reduzir a imagem. Rode com: python3 -I scripts/gen-windows-ico.py
"""
import os
import struct
import subprocess
import tempfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
source = os.path.join(root, "Resources", "AppIcon-windows-1024.png")
target = os.path.join(root, "windows", "Bkdict", "Assets", "AppIcon.ico")
sizes = [16, 24, 32, 48, 64, 128, 256]

frames = []
with tempfile.TemporaryDirectory() as temp:
    for size in sizes:
        path = os.path.join(temp, f"{size}.png")
        subprocess.run(["sips", "-z", str(size), str(size), source, "--out", path], check=True, capture_output=True)
        with open(path, "rb") as file:
            frames.append(file.read())

os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, "wb") as ico:
    ico.write(struct.pack("<HHH", 0, 1, len(sizes)))
    offset = 6 + 16 * len(sizes)
    for size, frame in zip(sizes, frames):
        side = size % 256  # 0 means 256
        ico.write(struct.pack("<BBBBHHII", side, side, 0, 0, 1, 32, len(frame), offset))
        offset += len(frame)
    for frame in frames:
        ico.write(frame)
print(os.path.relpath(target, root))
