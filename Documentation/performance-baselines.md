# Initial performance baselines

Measured on 2026-07-31 on Apple Silicon using the debug SwiftPM test build. These
are observational baselines, not pass/fail thresholds.

| Scenario | Workload | Mean wall time | Peak physical memory |
| --- | ---: | ---: | ---: |
| Recursive discovery | 5,000 PNG files in 50 directories | 0.43 s | 44 MB |
| Deterministic JSON encoding | 10,000 result records | 0.07 s | 56 MB |
| Concurrent WebP batch and progress | 100 images and 100 UI callbacks | 1.74 s | 20 MB |

The WebP batch includes bounded concurrency and 100 main-actor progress
callbacks. XCTest records current clock and memory figures in each run so they
can be promoted to an Xcode baseline after representative release hardware is
selected.

The metrics deliberately have no fragile hard limits.
