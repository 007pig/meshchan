# Phase 1D.11 USB native/POSIX controls — November 16, 2026

Status: **intermittent header-only initialization failure reproduced through
independent OS reads; exact firmware/USB/host-driver cause remains unconfirmed**.
This is initialization research, not GUI/RF acceptance. Candidate status remains
**prepared / acceptance incomplete**.

## Authorization, sources and fixed plan

After the [earlier single trace and three-attempt cohort](phase-1d11-usb-initialization-investigation.md),
the operator granted ten more attempts to reproduce and investigate. The current
explicit authorization superseded the earlier three-attempt/first-failure stop
only for this new cohort. The selected USB A was unchanged; B remained closed.
Every attempt retained request/init/write budgets of 15/30/2 seconds and zero
startup delay, with no application sends, inbox reads, firmware change, reset,
line toggle, input flush or repair query. Known initialization timeouts could
continue only after confirmed zero-send/read, known local writes, actual cleanup,
OS exit/reap and absent port owner. Unknown ownership/write/cleanup or an
unexpected control failure would stop the cohort.

The predetermined order was five native/POSIX pairs, **ten total acquisitions**.
No additional acquisition was made for setup or verification. macOS native port
metadata enumeration and OS ownership checks did not open the port. Each case
had separate preflight, execution and post-verification gates in the existing
runner. The finite cohort orchestration is external evidence, not a second
project regression framework.

The native cases reused the complete unchanged diagnostic bundle, executable
SHA-256 `c14749c9aee889d1f3dd27c9eb95b715476e4b9513fa937740ee464b7b6f2b87`.
The independent POSIX control is `tool/trace_usb_initialization.py`; it uses one
nonblocking macOS fd with exclusive access and direct standard-library
`os.write`, `select` and `os.read`, without Dart, libserialport, a background
reader, GUI or business storage. It checks raw 115200/8N1/no-flow termios state
using TCSANOW, preserving other output-line policy and performing no explicit
RTS/DTR ioctl. Actual iflag/oflag/cflag/lflag were 0/0/51968/0, speeds 115200.

The inert link-member `initialization_wire_plan.dart` uses the public codec to
emit only DEVICE_QUERY and APP_START. The POSIX tool independently validates the
exact fixed plan before opening: five query bytes, target 3, nineteen APP_START
bytes, reserved zero bytes and app name Meshchan. It cannot select another
command or take arbitrary timeout/retry settings. Only after complete selected
board DEVICE_INFO can it send APP_START. It retains only frame lengths/opcodes,
chunk lengths, times, accepted counts and safe structural errors, never raw
receive bytes or display/key fields. Bytes read after deadline cannot become a
successful reply. At timeout it makes bounded read-only FIONREAD/select/final
nonblocking-read observations on that **same fd**, then closes.

POSIX PASS means the selected board's complete DEVICE_INFO/SELF_INFO structures
(82/64 content bytes, protocol 14) arrived and close completed. It is explicitly
not `MeshCoreSession.ready` or a complete independent Companion implementation.
Native PASS uses the real Meshchan session. Neither is a GUI acceptance PASS.

The actual host was **macOS 27.2.1, build 26B131, arm64**. Python was
`/opt/homebrew/bin/python3` **3.15.2**; Dart was the installed Flutter 3.50.0
bundle's **3.14.0**. The actual baseline merge remained
`0fd49a3495d972c88dee35fc709501db78a16d16` plus the documented dirty beta/tools
source cut. The delivered beta `0.1.0-beta.1+3` app/CLI inventories and root lock
were verified unchanged before and after hardware execution. Firmware identity
remains the earlier U01 report/operator provenance, not a new flash readback.

## Ten actual attempts

All local writes accepted exactly 5/5 DEVICE_QUERY and 19/19 APP_START bytes.
Every case confirmed cleanup, OS exit/reap and an unoccupied port. There were
no runner signals, unconfirmed writes, application sends, inbox reads, B sessions
or retries inside an attempt. Failures were retained, not replaced by later PASS.

| Attempt | Backend | Result | Native/OS read chunk lengths | Whole process operation interval |
| --- | --- | --- | --- | --- |
| 1 | Native | PASS | 341, 67 | 247290 us |
| 2 | POSIX | PASS | 85, 67 | 6058 us |
| 3 | Native | PASS | 85, 67 | 245224 us |
| 4 | POSIX | PASS, delayed body | 3, 82, 3, 111 | 5832662 us |
| 5 | Native | PASS | 132, 67 | 239356 us |
| 6 | POSIX | PASS | 3, 59, 23, 67 | 6474 us |
| 7 | Native | FAIL, APP_START requestTimeout | 85, 3 | 15160683 us |
| 8 | POSIX | FAIL, APP_START requestTimeout | 14, 71, 3 | 15006140 us |
| 9 | Native | PASS | 85, 67 | 244257 us |
| 10 | POSIX | PASS | 85, 67 | 7188 us |

The interval includes setup/close and is not a LoRa RTT. Native library reads
use the existing 100 ms read timeout/5 ms loop yield; POSIX reads immediately
when select reports input, with no artificial read delay. Their chunk sizes and
timing are not interchangeable USB packet captures. Each backend had four PASS
and one FAIL in this small fixed sample; these are case counts, not reliability
percentages or a causal backend comparison.

## Fresh independent failure and kernel tty observations

Attempt 7 (PID 65123) received complete DEVICE_INFO, accepted APP_START and then
only a header declaring 64 content bytes. It failed with requestTimeout at
15002398 us after APP_START began; final trace was **3 of 67 bytes**.

Attempt 8 (PID 65285), 12:16:21.892756..12:16:36.898896 UTC, independently received
complete DEVICE_INFO through OS reads of 14 + 71 bytes. APP_START accepted all
19 bytes at trace offset 2885 us; the next read returned the three-byte header
at 3428 us. No content byte followed within the original deadline. At offset
15003298 us, requestTimeout was recorded, **15000413 us after APP_START**. The
slight overshoot is observed scheduling/probe time, not a larger configured
budget. No late data was accepted.

At that deadline on the same open fd:

| Probe | Actual result |
| --- | --- |
| FIONREAD before final read | 0 bytes |
| select with zero timeout | Not readable |
| Final nonblocking os.read | 0 bytes; not EAGAIN under this VMIN=0 setup |
| FIONREAD/select afterward | 0 bytes / not readable |
| Parser projection | 3 received of 67 expected, zero content, zero discarded bytes |

This fresh independent control establishes that the missing 64 bytes were not
available in the public tty input stream, were not returned by OS reads and then
discarded by a client parser, and were not merely waiting in a Dart subscription.
Flutter, recording/storage, Dart, libserialport and its reader are unnecessary
for the reproduced header-only symptom. It does not prove the bytes were absent
from driver-private buffers, emitted by firmware, retained by an endpoint or
permanently lost. No USB bus or device-side trace was captured.

The two failures had **no extra data preceding complete DEVICE_INFO** (85 total
bytes), so a 256-byte unsolicited backlog is not required for this symptom.
Both fail at APP_START/expected SELF_INFO, whereas the older GUI U02 failures
waited for DEVICE_INFO. The exact cause of those earlier first-step failures is
still not directly established.

## Delayed delivery without any extra host command

Attempt 4 is a separate useful observation. APP_START began at 2683 us; only
the three-byte header arrived at 3138 us. At 5829218 us, an OS read returned
111 bytes, decoded in order as the missing **64-byte SELF_INFO body** followed
by a **47-byte frame** (three-byte header + 44-byte `0x88` notification). The body
thus arrived **5826080 us after its header**, within the unchanged 15-second
deadline. It completed successfully. Exactly two host writes occurred; the
control sent no repair query or other release traffic.

At least this case demonstrates delayed rather than permanently absent content.
Its arrival with additional device data is consistent with USB full-packet
completion/ZLP buffering; it is a correlation, not a bus-level proof of cause.
Firmware scheduling or another driver/endpoint mechanism is not excluded.
Do not project this body's eventual delivery onto the two timeout cases.

## Mechanism assessment and fix boundary

The combined evidence makes a device/USB/host-driver completion problem the
leading direction. In the reviewed Arduino 2.0.17 HWCDC ISR, an empty ring has no
explicit final-ZLP branch; the later official
[TX fix](https://github.com/espressif/arduino-esp32/commit/2ecad233178bfbba9c584ffd9f67e941d84adbb7)
adds that branch along with other TX race/partial-write corrections. MeshCore's
reviewed serial writer submits header/body separately. These source facts fit
the current 64-byte-body delay/timeout but do not attest the loaded firmware
image or demonstrate which code branch executed on A.

Espressif's [current controller guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-guides/usb-serial-jtag-console.html)
also describes output that may remain buffered until further device traffic or
appropriate completion. It is newer general guidance, not the driver version
loaded on A. The [reviewed Offband per-frame patch](https://github.com/OffbandMesh/meshcore-firmware/pull/1143)
arms on whole-frame multiples of 64; a normal 3 + 64 = **67-byte** frame does not
meet that predicate. Its mechanism remains relevant but that exact patch is not
a verified remedy for this reproduction. Host serial flush/drain is not an
equivalent to device USB IN endpoint completion.

No production workaround, dependency/SDK change, timeout increase, startup sleep,
extra command, padding, firmware patch/flash or altered product assertion was
introduced. The remaining discriminator is device-side or USB bus evidence of
the final 64-byte transfer and its termination; repeated uninstrumented GUI
tries alone cannot locate that boundary. Such work was not executed in this
ten-attempt allowance. No GUI or RF acceptance result was promoted to PASS.

## Software checks and evidence

Before hardware, the independent POSIX tool passed **11 focused tests** covering
exact command/version rejection before open, all two-part frame splits,
partial/noisy input, redaction, overflow, timeout/final read, late-response
rejection, primary failure preservation and close after errors. Complete Python
discovery passed **135 tests**. An earlier intermediate source cut passed
10 focused / 134 complete tests; both cuts/receipts remain retained. The added
eleventh case tightened deadline/probe failure checks before hardware began.

The pure Dart wire generator passed analysis and actual inert emission/byte
validation. The existing app Device process gate passed using its public fake
transport and real worker/storage owner/contender paths, with **hardware=false**.
Its explicit fault fixture remains abnormal-exit evidence, not normal cleanup.
Closed fixtures were collected only after the runner confirmed process exit and
reap. These checks do not prove actual nested native-reader timing or GUI USB.

New source files are `tool/trace_usb_initialization.py`, its focused test and
`packages/meshcore_link/tool/initialization_wire_plan.dart`. The existing native
trace entry/support and all delivered product binaries are unchanged. No product
library, wire/database/summary/CLI schema or dependency graph changed. Current
CI discovery includes the hardware-free tests; no valid device execution was
added to CI.

Owned evidence root:
`/private/tmp/meshchan-1d11-20261116-01/hardware/usb-init-controls-01/`.
It contains the fixed case/authorization plans, original wire plan, per-case
preflight/trace/result, existing-runner receipts/logs, safe OS observations,
software fixtures, source hashes and a final manifest. Draft upstream reporting
is local only; no issue, message, firmware or binary was published. **10/10
attempts used; all consumers closed; further hardware paused.**

The operator then prioritized a consecutive-request solution. A separate
[completion-query candidate](phase-1d11-usb-completion-candidate.md) was prepared
and software-tested after this cohort. Its later, separately authorized four-case
hardware comparison is recorded there and does not alter these ten results.
Exact executed source bytes are retained in
`used-source/`, independently of the later source-tool candidate changes.
