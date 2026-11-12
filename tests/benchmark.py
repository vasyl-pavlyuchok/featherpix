#!/usr/bin/env python3
"""Measure Featherpix on a real batch: total size, saving and visual similarity (SSIM).

Usage: python3 tests/benchmark.py <folder> [fmt:quality[:maxwidth] ...]
Example: python3 tests/benchmark.py ~/imgs webp:75 avif:55
Uses the CLI inside build/Featherpix.app (run scripts/build-app.sh first).
Needs Pillow (with WebP/AVIF) and numpy. Dev tool only — the app does not need Python.

SSIM is computed on luma, 8x8 blocks, against the original resized to the output size
(so a width limit is not counted as a quality loss). 1.0 = identical; >0.95 is hard to tell apart.
"""
import subprocess, sys, tempfile, time, pathlib
import numpy as np
from PIL import Image

def ssim(a, b):
    a = np.asarray(a.convert("L"), dtype=np.float64); b = np.asarray(b.convert("L"), dtype=np.float64)
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    h, w = (a.shape[0] // 8) * 8, (a.shape[1] // 8) * 8
    A = a[:h, :w].reshape(h // 8, 8, w // 8, 8).swapaxes(1, 2)
    B = b[:h, :w].reshape(h // 8, 8, w // 8, 8).swapaxes(1, 2)
    ma, mb = A.mean((2, 3)), B.mean((2, 3)); va, vb = A.var((2, 3)), B.var((2, 3))
    cov = ((A - ma[..., None, None]) * (B - mb[..., None, None])).mean((2, 3))
    return float((((2 * ma * mb + c1) * (2 * cov + c2)) / ((ma ** 2 + mb ** 2 + c1) * (va + vb + c2))).mean())

cli = str(pathlib.Path(__file__).resolve().parent.parent / "build/Featherpix.app/Contents/Resources/bin/featherpix-cli")
src = pathlib.Path(sys.argv[1]).resolve()
confs = sys.argv[2:] or ["webp:75", "avif:55", "jpeg:80"]
originals = sorted(p for p in src.rglob("*") if p.suffix.lower() in {".jpg", ".jpeg", ".png"})
orig_total = sum(p.stat().st_size for p in originals)
print(f"batch: {len(originals)} images, {orig_total/1e6:.2f} MB")
print(f"{'config':<16}{'MB':>8}{'saved':>8}{'SSIM avg':>10}{'SSIM min':>10}{'time':>8}")
for c in confs:
    fmt, q, *mw = c.split(":")
    with tempfile.TemporaryDirectory() as out:
        args = [cli, "-f", fmt, "-q", q, "-o", out, "--keep-larger", str(src)]
        if mw: args[1:1] = ["-w", mw[0]]
        t = time.time(); r = subprocess.run(args, capture_output=True, text=True); dt = time.time() - t
        if r.returncode != 0:
            print(c, "FAILED", r.stdout[-500:], r.stderr[-500:]); continue
        outs = {p.relative_to(pathlib.Path(out) / src.name).with_suffix(""): p
                for p in (pathlib.Path(out) / src.name).rglob("*") if p.is_file()}
        total = sum(p.stat().st_size for p in outs.values())
        scores = []
        for o in originals:
            key = o.relative_to(src).with_suffix("")
            if key not in outs: continue
            ob = Image.open(outs[key]); oa = Image.open(o).convert("RGB")
            if oa.size != ob.size: oa = oa.resize(ob.size, Image.LANCZOS)
            scores.append(ssim(oa, ob))
        print(f"{c:<16}{total/1e6:>8.2f}{100*(1-total/orig_total):>7.0f}%{np.mean(scores):>10.4f}{min(scores):>10.4f}{dt:>7.0f}s")
