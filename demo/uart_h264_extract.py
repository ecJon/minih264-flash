#!/usr/bin/env python3
"""Extract the ESP32 demo's base64 frame dump from an idf.py monitor capture
into a playable Annex-B .h264 file.

Usage:
    idf.py -p PORT monitor > capture.txt      # on the host, while the demo runs
    python3 uart_h264_extract.py capture.txt device.h264

Then play / convert:
    ffplay device.h264
    ffmpeg -r 30 -f h264 -i device.h264 -c copy device.mp4
"""
import base64
import re
import sys

cap = open(sys.argv[1], "r", errors="replace").read()
out = open(sys.argv[2], "wb")

frames = 0
bytes_total = 0
cur = None
expect_len = 0

for line in cap.splitlines():
    m = re.search(r"\[B64 (\d+) (\d+)\]", line)
    if m:
        cur = []
        expect_len = int(m.group(2))
        continue
    if "[/B64]" in line and cur is not None:
        data = base64.b64decode("".join(cur))
        if len(data) != expect_len:
            print(f"warning: frame {frames} length {len(data)} != marker {expect_len}")
        out.write(data)
        frames += 1
        bytes_total += len(data)
        cur = None
        continue
    if cur is not None:
        s = line.strip()
        if s and re.fullmatch(r"[A-Za-z0-9+/=]+", s):
            cur.append(s)

out.close()
print(f"frames: {frames}, bytes: {bytes_total} -> {sys.argv[2]}")
if frames == 0:
    sys.exit(1)
