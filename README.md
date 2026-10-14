# KV260 Mega Drive core

Development sources for the K26 (`xck26-sfvc784-2LV-c`) Mega Drive core. Prepared Genesis sources derive from `Genesis_MiSTer` commit `adc0c42cfb1fa5d484cc8566767f7d68982bc44a`; upstream licenses are retained.

The current MD video fault is unresolved on physical hardware. Included read-only video probes aid diagnosis; this snapshot is not a validated repair.

GitHub Actions uses a public Linux runner and four Vivado threads. The runner precheck measures available CPUs, memory and disk. Vivado 2026.1 is supplied separately in a private GHCR image; no AMD binaries, certificates, commercial game ROMs or local credentials are committed. Set repository variable `VIVADO_IMAGE` to a pinned image digest and repository secret `VIVADO_LICENSE` to a certificate issued for this dedicated cloud host.

Run **Vivado 2026 cloud**, first `runner-check`, then `toolchain-check`. The latter verifies version, K26 board/IP availability and a tiny K26 synthesis/implementation license checkout. The `synth-review` phase runs full MD synthesis and exports the constrained checkpoint, CDC reports and source identity; routing requires review tied to the exact checkpoint.

Cloud host identity: `md-ci-vivado`, Ethernet `02:4d:44:26:01:01`. Obtain a separate certificate for this identity; do not transfer or change the certificate used by local builds.

The pending full-build artifact is `MD03-Diag-2026.k26`, a read-only diagnostic
observer rather than a rendering repair. See [MD03 observation protocol](reference-docs/MD03_DIAGNOSTIC.md)
for whole-frame counts, fixture restrictions and remaining hardware validation.
