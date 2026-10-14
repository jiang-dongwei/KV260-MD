# MD03 diagnostic observation (cloud Vivado 2026.1)

MD02-Diag on hardware retains one complete native and post-cofi line. Its four
H32 samples are correct while capture rings remain corrupt. MD03 adds full-frame
line totals so one correct retained line cannot hide faults elsewhere.
This is read-only instrumentation, not a rendering repair.

The existing acknowledged 32-bit snapshot publishes C/D/E/F stages in turn at
post-cofi vertical blank. MMIO remains the side-effect-free aligned 32-bit status
at offset 0x34. The package identity must match before mapping or sampling.

| Tag | Bits27:18 | Bits17:9 | Bits8:0 |
| --- | --- | --- | --- |
| E | Native complete-line width | Native complete lines | Native incorrect lines |
| F | Post-cofi complete-line width | Post-cofi complete lines | Post-cofi incorrect lines |

C/D keep the MD02 layout: native width in bits27:18, stream width in bits17:8,
four two-bit colors at x32/96/160/224 in bits7:0. Blue0/red1/green2/other3.

For the original H32/H40 video diagnostics, E/F check every active pixel for
literal red-left/green-right colors and complete widths of 256 or 320. Width
reference is learned from the preceding complete line; cold start or mode
changes can produce transient failures. Wait for stable observations. Disable
Composite Blend when interpreting exact post-cofi primary-color checks.
The counters are not a game-content health test.

A VBL release within an active line is excluded until a subsequent HBL-to-active
start; a VBL assertion truncating the end is excluded too. Counters saturate at
511 and reset once per frame. Complete-line totals therefore need not be 224.

Focused RTL verification passes H32/H40, delayed independent stream observations,
all-pixel clean-frame counting, an injected corrupt pixel at x17 on one middle
line (outside the older sample points), mid-line VBL release, and coherent
unequal-clock mailbox delivery. A startup fixture initially emitted an empty
VBL before its first visible frame; corrected the fixture's frame schedule.
This was not a video-core repair.

Full cloud synthesis, constrained CDC review, routing, timing, bitstream and
package export remain required. Physical observation of MD03 remains pending.
MD01 and the successfully built/local MD02-Diag packages remain unchanged.
