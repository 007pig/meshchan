# Meshchan RC1 Build 10 candidate validation

This receipt summary applies to compiled source `c5cd5021da5e62c60127678b650d970721263296` and
the 669,400,332-byte DMG with SHA-256
`0f7232479e33cdfb28862b2253bfdd92aad623f985e4fbe9a89989cab949e4bb`. The candidate uses the local-adhoc profile
for Meshchan App `0.1.0-rc.1+10` and `meshctl 0.1.0-rc.1`.

| Gate | Status | Observed scope |
| --- | --- | --- |
| Frozen build and product path scan | PASS | Clean Recipe 57 source, exact App and CLI identity, native paths checked across eight Mach-O files. |
| Strict materials and frozen recheck | PASS | SDK and build-time native replacement, strict corresponding-source and materials, and independent frozen recheck. |
| Package and independent extraction | PASS | Exact archive producer and independent check, each with extracted offline CLI and VM App runtime verification. |
| Independent local-adhoc signing | PASS | Independent private signed product, exact CLI runtime, guest App offline runtime and signed synthetic replacement. |
| DMG and payload privacy | PASS | Creation and independent read-only extraction with code signatures, offline CLI and VM App runtime. Both audits report 693 image entries, 403 first-party archive entries, eight Mach-O files and zero findings. |
| Candidate admission | PASS | The exact independently checked public engineering image passed candidate admission. |
| Exact extracted CLI help and version | PASS | Exact independently extracted App plist matched the public manifest. CLI version and global help returned exit 0, with empty stderr. |
| Public native replacement on engineering extraction | PASS | The exact signed App and CLI were separately re-signed, loaded the shipped tool’s synthetic serial library and exited normally. The App was measured in a paired VM from the engineering extraction. |
| Co-located installation layout | PASS | In the registered macOS VM, the complete unquarantined independent extraction matched 693 image entries and eight code-signature policy items in a fresh co-located Applications fixture. The owned fixture was cleaned up. |
| Quarantined clean download, approval and runtime | PASS | The exact image was downloaded with Safari and installed together in a fresh independent host-only macOS 27.2.1 (26B131) arm64 VM. Native download quarantine, App item approval, CLI and SQLite approval dispositions, offline Save, owner contention, and normal Quit and reopen were verified. |
| Normal approval and runtime of quarantined replacement copies | PASS | The maintainer used the shipped rebuild and signing code and same-guest copies of the exact Safari installation. Both products loaded their mapped synthetic libraries and exited normally. The CLI returned empty ports, and the App showed empty ports after Refresh. The receipt confirms the original Safari quarantine event and normal system protections. |
| Beta CLI-closed fixture | PASS | The exact App opened an owned closed Beta data fixture, added one draft and quit normally. The exact CLI completed 28 independent reads, confirming five drafts, six profiles, one settings row and 12 History entries. |
| Full historical Beta Finder upgrade | BLOCKED | The retained signed historical Beta App lacks 15 required entries. The closed Beta data fixture result has different scope. |
| Exact-image real USB Device Check | NOT_RUN | Requires separate accepted exact-image hardware evidence. |
| Exact-image finite RF and active Cancel | NOT_RUN | Requires a separate accepted finite run on this image. |
| Exact-source local Python tests | PASS | 719 tests on Python 3.15.2 under standard umask 022, 338.690 seconds. |
| Exact-source CI | OPEN | No remote exact-source CI in the local frozen workflow. |
| Durable retention and independent restore | OPEN | Seal with the exact eligible CI chain and independently restore the selected image. |
| Publication and actual public downloads | HELD | No tag or publication authorization in this run. |

The shipped replacement command was exercised end to end on the engineering
extraction. The quarantined runtime test used host preparation and native
execution on same-guest copies. Direct invocation of the shipped preparation
command against the quarantined Safari installation remains unverified.

Earlier Build 9 and Build 10 receipts retain their own image identities.
Publication remains blocked. The proposed attachment manifest maps the
available files and records the candidate state.

See the [engineering guide](rc1-build10-engineering-guide.md) and the
[source and license index](rc1-build10-source-materials.md).
