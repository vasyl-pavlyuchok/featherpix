# Benchmark — real batch

**Batch:** 325 UI/design reference images (contact sheets and boards from a design skill), JPEG,
900–1482 px wide, **30.98 MB** in total. They were already compressed JPEGs, which makes this a
*hard* batch: the gains on camera photos or PNG screenshots are usually larger.

**Machine:** Intel Mac (x86_64), macOS 14, Featherpix 1.0.0 (`featherpix-cli`), measured
12 Nov 2026 with `tests/benchmark.py`.

**SSIM** = structural similarity on luma, against the original resized to the same size
(1.0 = identical; above ~0.97 differences are hard to see at 100 %).

| Setting | Total | Saved | SSIM avg | SSIM min | Time |
|---|---:|---:|---:|---:|---:|
| WebP 85 | 27.02 MB | 13 % | 0.991 | 0.954 | 111 s |
| **WebP 75** (default) | 18.70 MB | 40 % | 0.985 | 0.914 | 83 s |
| WebP 60 | 15.80 MB | 49 % | 0.981 | 0.889 | 95 s |
| WebP 60 · ≤1200 px | 14.33 MB | 54 % | 0.980 | 0.889 | 57 s |
| AVIF 55 | 16.42 MB | 47 % | 0.990 | 0.952 | 174 s |
| **AVIF 45** (default) | 12.10 MB | 61 % | 0.984 | 0.904 | 114 s |
| AVIF 40 | 9.74 MB | 69 % | 0.977 | 0.863 | 103 s |
| **AVIF 40 · ≤1200 px** (preset *Smallest*) | **8.85 MB** | **71 %** | 0.975 | 0.863 | 151 s |
| **JPEG 75** (mozjpeg, default) | 27.40 MB | 12 % | 0.996 | 0.985 | 21 s |
| JPEG 70 (mozjpeg) | 24.86 MB | 20 % | 0.990 | 0.931 | 25 s |
| JPEG 80 (mozjpeg) | 32.03 MB | −3 % | 0.998 | 0.989 | 31 s |

**Goal met:** the whole batch fits under the 10 MB browser upload limit with the
*Smallest* preset (8.85 MB, −71 %) or AVIF 40 at full width (9.74 MB).

Note from the first run: macOS's built-in JPEG encoder (ImageIO) made this batch **66 % bigger**
at quality 80, which is why Featherpix ships mozjpeg instead.

Reproduce: `scripts/build-app.sh && python3 tests/benchmark.py <folder> webp:75 avif:40:1200`
