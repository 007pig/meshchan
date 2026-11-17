# Phase 1E.3 distribution materials

The maintainer selected **GNU GPL version 3 only (`GPL-3.0-only`)** for all
first-party contributions, with `Copyright (c) 2026 Meshchan Contributors`.
The [decision record](project-license-decision.json) retains 007pig's explicit
authority over all first-party contributions and confirmation of no exceptions.
The latest GPL decision supersedes the earlier MIT selection. The unmodified
GNU license text is in the repository root LICENSE; COPYRIGHT applies it to
Meshchan and records the chosen attribution. No later GPL version is inferred.
Third-party notices retain their original scope and bytes.

Incoming contributions follow root CONTRIBUTING.md and CLA.md, version 1.0
(meshchan-cla-1.0). Contributors retain ownership while separately authorizing
007pig to use covered contributions in GPL community and paid, closed-source
commercial editions with sublicensing. Each grant requires the contributor's
recorded acceptance and the Recipient's acknowledgement; publishing this policy
does not prove that any contributor already signed or that earlier GPL authority
includes proprietary relicensing rights. The root GPL text remains unchanged.

This closes the maintainer-decision gate. GPL adds corresponding-source
obligations to the product distribution: the previous permissive-license review
is not sufficient to close those requirements. Strict collection now preserves
first-party source/build inputs, all production/helper pub archives, selected
Flutter framework/build/engine sources, and the exact Dart runtime/library
sources. The [native SDK source supplement](phase-1e3-sdk-sources.md) supplies fixed
engine/Dart/native/LLVM archives, build inputs and executable reconstruction rules.
The fatal source gate now requires fresh independent source and GN closure checks;
root LICENSE or a cached PASS cannot satisfy it. See the validation record for
the current candidate result; public release still requires subsequent steps.

## Collection and strict checking

Use the installed SDK and Python, without upgrades. From the repository root:

```sh
/opt/homebrew/bin/python3 --version
PATH="/opt/homebrew/share/flutter/bin:/usr/bin:$PATH" /opt/homebrew/share/flutter/bin/flutter pub get --enforce-lockfile
/opt/homebrew/bin/python3 tool/release_sdk_sources.py check --workspace build/phase-1e3-source --flutter /opt/homebrew/share/flutter
/opt/homebrew/bin/python3 tool/release_materials.py collect --flutter /opt/homebrew/share/flutter --app build/phase-1e3-trusted-build7/app-derived/Build/Products/Release/Meshchan.app --cli build/phase-1e3-trusted-build7/cli/bundle --downloads build/phase-1e3/downloads --output build/phase-1e3-trusted-build7/materials --probe build/phase-1e3-trusted-build7/evidence/serial-rebuild.json --sdk-source-workspace build/phase-1e3-source --build-inputs build/phase-1e3-trusted-build7/evidence/compilation-input-hashes.json --candidate-hashes build/phase-1e3-trusted-build7/evidence/candidate-checksums.txt --build-receipt build/phase-1e3-trusted-build7/evidence/build-receipt.json
/opt/homebrew/bin/python3 tool/release_materials.py check --flutter /opt/homebrew/share/flutter --app build/phase-1e3-trusted-build7/app-derived/Build/Products/Release/Meshchan.app --cli build/phase-1e3-trusted-build7/cli/bundle --downloads build/phase-1e3/downloads --output build/phase-1e3-trusted-build7/materials --probe build/phase-1e3-trusted-build7/evidence/serial-rebuild.json --sdk-source-workspace build/phase-1e3-source --build-inputs build/phase-1e3-trusted-build7/evidence/compilation-input-hashes.json --candidate-hashes build/phase-1e3-trusted-build7/evidence/candidate-checksums.txt --build-receipt build/phase-1e3-trusted-build7/evidence/build-receipt.json
```

`collect` can emit REVIEW_REQUIRED with open gates. `check` returns nonzero for
those gates even if integrity and independent coverage pass. It recomputes
coverage from the actual lock, graph, package configuration, SDK and complete
products, and verifies every collected file. Removing a required manifest entry
cannot bypass coverage. A new collection needs a new output directory; downloads
can be reused only with their locked archive hashes. Failed downloads never
repair or remove user caches. The checker is offline after required downloads.
Material files retain original bytes. Manifest ordering is stable, and timestamps
are kept out of content identity. Source hashes include relevant working-tree
files; the outcome validation document is excluded to avoid a reporting cycle.
Declared output, download and SDK-source workspace trees are also explicitly
excluded from the repository source snapshot, including non-ignored locations
such as `dist/materials`. Collect and check use the same exclusions. A generated
directory cannot hide tracked source or Git metadata. Keep large delivery files
in ignored `build/` for normal use.

## Component and obligation matrix

| Component | Products and evidence | Materials and obligation |
| --- | --- | --- |
| Four workspace members | First party; production roots App and CLI | GPL-3.0-only, approved by 007pig; retain COPYRIGHT/LICENSE and corresponding source. Never list as third-party authors. |
| Hosted production closure | App-only, CLI-only and shared in manifest | Exact locked archives cross-check cache files; preserve original root and nested notices. No claim that all declared dependencies survive AOT. |
| Hook helper closure | Both products' declared graph; exact reviewed hook imports annotate build edges | Preserve notices conservatively and key helper source archives for rebuilding. Never prune a name globally when it also has a runtime edge. |
| libserialport_plus 1.0.5 | MIT Dart wrapper | Original package LICENSE and copyright. |
| Embedded libserialport | LGPL-3.0-or-later C code, both native bundles | Original README, COPYING (LGPLv3), GPLv3, full locked archive, src/include/config.h, complete C source tree, hook and package metadata; independent modified-library experiment below. |
| sqlite3 3.9.1 | MIT Dart wrapper; separate native default SQLite asset | Wrapper notices and hook/hash sources; raw native asset and per-architecture section mapping to bundle. Fixed upstream release build evidence must identify SQLite source/version and extensions. Public domain does not extend to the wrapper or unrelated variants. |
| Flutter framework | App production graph, actual framework revision | Framework LICENSE and package notices. SDK package 0.0.0 is not a framework version. |
| Flutter engine, App Dart runtime, ICU | Actual FlutterMacOS framework slices, matching SDK artifact sections | Engine-wide sky_engine/LICENSE aggregate and official SDK archive pointers; preserve ICU and nested notices. App NOTICES.Z is independently retained and decoded. |
| CLI Dart AOT runtime | Exact bundled Dart version/revision and dartaotruntime sections | SDK LICENSE plus engine-wide aggregate are collected. The exact SDK runtime/DEPS and official aggregate correspondence is described below; a root LICENSE or pointer alone is insufficient. |
| Material Icons | Actual FontManifest and bundled subset font | Original SDK MaterialIcons license, source-font hash, bundle-font hash and App-notices cross-check. No Roboto font is asserted to ship. |
| System frameworks/libraries | otool loader entries under /usr/lib and /System/Library | OS supplied, not copied into the product; distinguish from bundled native code. |

Native evidence permits compatible cross-product hook cache reuse. Each raw asset
must match all file-backed sections in the corresponding target slice, with
matching platform/architecture and current dependency metadata. Install-name and
signature bytes are separate from section hashes; this is a bounded correspondence
check, not an assertion of identical binary bytes or formal signature acceptance.
Multiple incompatible/ambiguous raw candidates fail. Extra x86_64 slices are
covered as shipped bytes and establish no Intel support.

## LGPL source, rebuilding and replacement

The original archive is identified by the lock's archive SHA-256, not a guessed
upstream tag. config.h says 0.1.1 and configure.ac says 0.1.2; source provenance is
the complete exact pub archive. Unknown upstream tag does not mean missing source.
The hook compiles serialport.c, timing.c and macosx.c as Objective-C with
LIBSERIALPORT_ATBUILD, src/include, IOKit and CoreFoundation. Preserve the entire
src tree, configuration, hook and archive rather than selected source fragments.

After collecting (or downloading and verifying the exact archive), run:

```sh
/opt/homebrew/bin/python3 tool/rebuild_release_serial.py --archive build/phase-1e3/downloads/libserialport_plus-1.0.5.tar.gz --archive-sha256 9246f3a0909e4bc87ef2ac1366bbc2eb350d139f976a277dd5c29b8d3dc085e3 --cli build/phase-1e3-trusted-build7/cli/bundle --app build/phase-1e3-trusted-build7/app-derived/Build/Products/Release/Meshchan.app --output build/phase-1e3-trusted-build7/evidence/serial-rebuild.json
```

The tool validates the archive, extracts it into a new /tmp directory, rebuilds
the unchanged library, and invokes only its version function through ctypes.
It then modifies sp_list_ports to return an allocated empty list before any OS
backend call, adds a diagnostic marker, and recompiles. It replaces only native
libraries in complete isolated candidate copies, adjusts their install names,
and signs those copies ad hoc. CLI `ports --json` must produce both the marker
and an empty list. It uses synthetic data, never a real port. App copy preparation
and deep signature verification are recorded separately from App runtime loading.
The original candidates, SDK and pub cache are never rewritten.

Adopt LGPLv3 section 4(d)(1)'s suitable shared-library mechanism only where actual
replacement works. Preserve the prominent library notice, both GNU license
texts and original copyright, and permit modifying the library and reverse
engineering the combined work for debugging those modifications. No project
license overrides these rights. The current About panel displays version and
has no first-party copyright notice; CLI help/version likewise has no copyright
display. Distribute the prominent notice beside both products; if a later product
displays copyright, include the library notice and GNU-license direction there
as required by section 4(c). No new About system is introduced in this step.

Provide the corresponding library source/build materials with the binary under
GPLv3 section 6(a), as incorporated by LGPLv3. Shared replacement does not waive
that library-source obligation or the GPL application-source obligation. Section 4(d)(1) does not require Meshchan AOT
application object files when the shared mechanism works. Installation information
under section 4(e) is needed only if otherwise required by GPLv3 section 6 and
only as needed to install/run a modified combined work. The local experiment
uses no keys or locked device. Do not prohibit users' local replacement/re-signing.
If final delivery imposes additional installation restrictions, 1E.6 must assess
and supply the needed information; do not infer a GPL license for the whole App.

## Handoff and distribution layout

1E.4 must bind fresh compilation inputs and complete products, then invoke this
collector. 1E.5 must stage the generated notices/licenses next to the App and CLI
in the DMG and include the source-materials and rebuild directories in that same
delivery or an immutable matching source attachment on the same release entry.
If network source delivery is used, supply an actual corresponding source download
beside the binary download, at no extra charge, with clear directions and continued
availability consistent with GPLv3 section 6(d). No future URL is invented here.
Do not ship raw private validation logs or arbitrary SDK/cache trees.

1E.6 must repeat modified-library loading and necessary local re-signing under
actual Developer ID/Hardened Runtime conditions, with an interface-compatible
modified library for both products, preserving the adopted rights. Local ad hoc
results do not establish those conditions. Recollect/recheck after any graph,
lock, SDK, engine, runtime, native, font/resource, product or signing change.
Future signed/stapled App, final DMG, extracted products and final checksum
identities are outside this current candidate review.

## Exact runtime and resource correspondence in this review

The installed SDK's archive pointers name engine revision
`371f77202a73e8dff57a8b3bff75bca55c090aee` and its `sky_engine.zip`.
The collector downloads that exact official artifact, verifies its pinned hash,
and compares the full 1,331,982-byte license aggregate to the installed original.
That SDK-wide aggregate includes engine third parties and Dart entries; it is
retained conservatively for both products, rather than selecting supposed runtime
entries by package name. Flutter DEPS pins Dart revision
`fa8c1270c374c1346931583a17c3b7f278d3822d`, matching the actual SDK revision.
All nonempty file-backed sections of the App engine match the installed release
artifact, and those of CLI's embedded runtime match this SDK's dartaotruntime.
The SDK runtime's empty `__CUSTOM/__space_for_note` reservation has no bytes and
becomes executable snapshot metadata; empty sections are excluded explicitly.
This binds CLI runtime materials independently of the App's automatic notices.
It is conservative official aggregate coverage, not a symbol-level third-party
minimization or a claim about all SDK compiler tools being shipped.

The Material Icons license in this installed SDK is **CC BY 4.0**, not an assumed
Apache license. Font name records say `Copyright 2019 Google LLC. All Rights
Reserved.` The collector verifies both the font and license against the exact
`material_fonts.stamp` archive. Generated THIRD_PARTY_NOTICES supplies attribution,
the source link, license link and the fact that Flutter generated a subset for
Meshchan. The original license is also retained separately because its exact text
was not found in the generated App notices. Do not rely on automatic NOTICES.Z to
satisfy the separate font or embedded LGPL notices.

SQLite's native asset reports **3.54.1**, source ID
`2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76`.
The release tag resolves to commit `f144d1c56b22d5772d164c7c3f20eb1df482fcf3`.
Its original download/build/workflow/SBOM recipes identify the default SQLite
amalgamation `3540100`, distinct from SQLCipher and Multiple Ciphers. The exact
amalgamation archive and original sqlite3.h (including public-domain declaration)
are retained and checked against the loaded source ID. The manifest records actual
compile options, raw locked-table download hashes, bundled hashes and per-slice
section mapping. No system SQLite substitution, database or extension load occurs.

For a new 1E.4 build, pass `--build-inputs PATH` (JSON mapping repository-relative
compilation input paths to SHA-256) and `--candidate-hashes PATH` (standard SHA-256,
two spaces, actual file path). The latter must cover actual App Info.plist,
runner, App.framework/App and CLI bin/meshctl, and all listed hashes are checked.
The legacy defaults point to 1E.2 records; the current build-7 commands explicitly
supply their new complete record and checksums. These are build evidence inputs,
not alternative license manifests. New SDK/asset
identities require reviewing and updating the fixed URL/hash source pins.

The required compilation inventory is independently derived from the four
workspace members: root/member manifests and lock, all member lib/bin/hook
inputs, root/member license/notice declarations used by automatic notices,
generation configuration, declared Flutter assets/fonts, and stable
macOS source/assets/project/workspace/scheme/configuration files. Ephemeral SDK
configuration, user Xcode state and native test-only files are separate. Empty
or partial build records fail; all additional recorded paths must also remain
valid and unchanged. The machine manifest preserves the independently required
hash map alongside the supplied build record.

Capture the complete map immediately before building, preserve it with the
actual build/checksum evidence, then compare it after the build. From the root:

```sh
/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart tool/release_materials_inputs.dart "$PWD" > build/workspace-inputs.json
PYTHONPATH=tool /opt/homebrew/bin/python3 -c 'import json; from pathlib import Path; from release_materials import compilation_inputs, encoded; print(encoded(compilation_inputs(Path.cwd(), json.loads(Path("build/workspace-inputs.json").read_text())["members"])).decode(), end="")' > build/compilation-input-hashes.json
```

These commands capture current input bytes; running them after an old build
does not reconstruct missing historical build evidence. Review found seven
uncaptured inputs in the existing 1E.2 record. The strict checker retains that historical gap. The current build-7 material
commands use a fresh before-build record and verified after-CLI/after-App
snapshots. The initial seven missing configuration inputs and the two root
license declarations are included in the new 137-entry map. No missing historical
hashes were filled with current bytes to make the old build pass.

For a contemporaneous build ledger, pass `--build-receipt PATH`. The checker
requires a successful App/CLI build, matching input/checksum/product identities,
unchanged before/after source maps, the exact runner-source hash and unchanged
local command logs. It collects the receipt, source snapshots and original
runner source. Raw build logs remain local; the receipt retains their hashes and
actual argv. This supplements the existing manifest without creating a release
pipeline or declaring a signed/public artifact accepted.

Current build-7 evidence was captured in a new output directory before compiling.
The installed Flutter generated configuration first; compilation then used the
standard Dart CLI builder and Xcode Release Runner scheme with explicit isolated
`-derivedDataPath`, `OBJROOT` and `SYMROOT`. The exact commands, tool versions and
before/after hashes are in the delivered build receipt. Historical build 6 is
preserved, and a preliminary build-6 trial containing new GPL notice bytes is
explicitly excluded from delivery. App fallback/native/manifest identity and the
existing CI assertions now agree on build `7`; CLI stays `0.1.0-rc.1`.

The current App modified-library observation used the existing VM skill and
product helper. Reproduce it after the isolated rebuild using its
reported `appPreparedCopy` below:

Attaching an observation preserves the original candidate hash. It first rejects
a different original runner or a prepared copy whose unchanged payload differs
from the supplied candidate, including App.framework and resources. The runner's
file-backed sections must match across local ad hoc re-signing. The collector
repeats this binding check. Only the replacement serial framework and expected
outer signing metadata are excluded; the VM observation must also bind the
prepared runner's actual executable hash.

```sh
app_copy=$(/opt/homebrew/bin/python3 -c 'import json; print(json.load(open("build/phase-1e3-trusted-build7/evidence/serial-rebuild.json"))["appPreparedCopy"])')
/opt/homebrew/bin/python3 apps/meshchan_app/tool/macos_vm/host.py --config ~/.config/meshchan-vm/config.json --evidence build/phase-1e3-trusted-build7/vm prepare
/opt/homebrew/bin/python3 apps/meshchan_app/tool/macos_vm/host.py --config ~/.config/meshchan-vm/config.json --evidence build/phase-1e3-trusted-build7/vm launch Release "$app_copy"
/opt/homebrew/bin/python3 apps/meshchan_app/tool/macos_vm/host.py --config ~/.config/meshchan-vm/config.json --evidence build/phase-1e3-trusted-build7/vm action Release nav Device
/opt/homebrew/bin/python3 apps/meshchan_app/tool/macos_vm/host.py --config ~/.config/meshchan-vm/config.json --evidence build/phase-1e3-trusted-build7/vm action Release click Refresh
/opt/homebrew/bin/python3 apps/meshchan_app/tool/macos_vm/host.py --config ~/.config/meshchan-vm/config.json --evidence build/phase-1e3-trusted-build7/vm action Release key q command
/opt/homebrew/bin/python3 apps/meshchan_app/tool/macos_vm/host.py --config ~/.config/meshchan-vm/config.json --evidence build/phase-1e3-trusted-build7/vm settled Release
/opt/homebrew/bin/python3 apps/meshchan_app/tool/macos_vm/host.py --config ~/.config/meshchan-vm/config.json --evidence build/phase-1e3-trusted-build7/vm finish
```

Use a new evidence directory on reruns. The helper verifies guest identity,
product PID/arguments/fixture, normal resource and worker release, and PID absence.
`Refresh` is safe here only because the replacement library returns an empty list
before reaching the OS backend. Attach the observation with the same rebuild
command plus `--attach-vm-evidence build/phase-1e3-trusted-build7/vm --vm-config ~/.config/meshchan-vm/config.json`.
That mode does not rebuild; it verifies the marker, normal close, source App path
and guest replacement-library hash, then updates the existing probe report.

Rule references: [LGPLv3](https://www.gnu.org/licenses/lgpl-3.0.en.html),
[GPLv3](https://www.gnu.org/licenses/gpl-3.0.html),
[Flutter LicenseRegistry](https://api.flutter.dev/flutter/foundation/LicenseRegistry-class.html),
[SQLite copyright](https://sqlite.org/copyright.html). Fixed version materials,
not these current web pages, supply the collected originals.


## GPL corresponding-source supplement

The approved root LICENSE is the canonical unmodified GPLv3 text. Its own FSF
copyright identifies the license document; Meshchan's separate COPYRIGHT records
`Copyright (c) 2026 Meshchan Contributors` and expressly applies version 3 only.
The collector binds both original files to hashes and maintainer authorization.
The first-party source snapshot also retains root CLA.md and CONTRIBUTING.md.
Preserve their exact versions and the acceptance records for any future
commercial-rights review. No CLA changes the community source-distribution
obligations or bypass the independent engine/runtime source check.

For the GPL products, source-materials now includes a deterministic first-party
source snapshot containing the four members, generated Dart code, native Runner
configuration/assets, tools, CI recipes, locked manifests, build instructions and
license/decision files. Source bytes used by the unchanged candidates remain
checked against their independent compilation-input record. All declared
production/helper hosted archives are retained at their lock hashes. Their own
MIT/BSD/etc. notices remain effective; this does not rewrite their original terms.

The [native SDK source supplement](phase-1e3-sdk-sources.md) documents exact
engine/framework Git tree equality, separate engine and standalone Dart DEPS,
original source archives, LLVM runtime/build source, compiler configuration,
three native GN roots and narrow upstream stale-header metadata exceptions.
`release_materials.py` now reruns that check, copies every required source archive
and build input, and binds the resulting graph evidence into this materials
manifest. Original archives preserve nested notices and checked-in regeneration
inputs. The delivered rules support reconstruction in a fresh owned directory.
A missing archive, source revision mismatch, missing generated-input producer,
changed source/script/build definition, absent native root or incomplete runtime
source set remains a fatal error. General-purpose compiler tools and actual
OS-provided libraries are separately identified; bundled runtime code is supplied
as source rather than excluded under a blanket SDK exemption.

Final binary distribution must provide the complete matching source with the
binary or equivalent access under GPLv3 section 6; the same release-entry
availability rules above apply. Fresh source coverage and current candidate
binding do not pre-approve future signed/DMG bytes or create a public release.

The LGPL shared-library experiment remains useful independent evidence. Its
section 4(d)(1) path does not remove the GPL source obligations now chosen for
Meshchan itself. Formal signing/installation-information validation remains
1E.6 work. The initial licensing review preserved build `6`; the subsequent trusted
candidate rebuild selects build `7` for the changed automatic notices. Product
logic, lock, data/schema/wire contracts and earlier candidate bytes are preserved.
