# Phase 1E.4 local Release build validation

## Recipe 55 handoff

On November 20, 2026, two independent Release builds used frozen source commit
`a29430b608658a8b56d619f641dc8600346b6d27`, based on the merge of PR #41 at
`583dc5f7ee9d5d173237e8eb60b06dd388304b80`. The bundle identity is App
`0.1.0-rc.1+8`, Apple version `0.1.0`, build string `8`, bundle ID
`org.meshchan.meshchan`, and CLI `0.1.0-rc.1`. The actual builder was macOS
27.2.1 arm64 with `/opt/homebrew/bin/python3` 3.15.2, Flutter 3.50.0, its
bundled Dart 3.14.0, Xcode 27.2 (27B52), Apple Clang 21, and macOS SDK 27.2.

**1E.5 reference** `build/phase-1e4/frozen-recipe-55/build/phase-1e4/run-001/`.
Consume the existing `app-derived/Build/Products/Release/Meshchan.app` and
`cli/bundle/` under that run, with the materials in `materials/`. The comparison
candidate is `run-002/` in the same frozen checkout. Its independent check
passed with materials status `NOT_RUN`.

| Reference evidence | SHA-256 |
| --- | --- |
| `build-info.json` | `e9e2eb640af06cdf8e70696a82cf45ce124e1682784b364698d4a9d73c3c56ef` |
| `evidence/compilation-input-hashes.json` | `f6adf08d910ef52cfa8031eb207f1adc51e7056cd8efc1a7bea9f34fa9c03fdb` |
| `evidence/build-receipt.json` | `5b99f6daf49b0af123e66641ba16ae20939a5b8fa6d2cda2dc941bee1a5d458a` |
| `evidence/candidate-checksums.txt` | `e69f1feb8125a1200778950a1bef292a61da9aef4ce533d55ceb8b1b897ae779` |
| `evidence/candidate-inventories.json` | `5261f1f685d9b63e0d6003fbc722ce866789cfa7cdfdfefadc54a4292eabfcaa` |
| `evidence/product-checks.json` | `94812a09ba168222f8775f017e57f297e7606b424f5944a619efbd4c4e034c29` |
| `materials/materials-manifest.json` | `335519433a4e48d2e683563d7104b2b84ff35f274a5895bb7f8329a1cd909733` |

From the retained frozen checkout, the recorded commands were:

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-001
/opt/homebrew/bin/python3 tool/build_release.py build --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-002
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-002
/opt/homebrew/bin/python3 tool/build_release.py materials --output build/phase-1e4/run-001 --downloads "$MESHCHAN_MAIN/build/phase-1e3/downloads" --probe build/phase-1e4/run-001/validation/serial-rebuild.json --sdk-source-workspace "$MESHCHAN_MAIN/build/phase-1e3-source"
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-001 --require-frozen
```

`MESHCHAN_MAIN` denotes the primary checkout used for the verified caches. Each
before/after map contained 137 identical inputs. The source, graph,
lock, toolchain, normalized recipe, configuration, external sources, product
composition, and loader checks matched across the runs. Each App inventory
contains 74 entries and each CLI inventory contains six. The comparison report
records all product differences. File-backed Mach-O sections and embedded CLI AOT
sections matched for the differing executables.

| Product file | `run-001` SHA-256 | `run-002` SHA-256 |
| --- | --- | --- |
| App Info.plist | `b5e2ae7b451eaa621906efa49789f42fe57c0469942ac62587307623876a638e` | `b5e2ae7b451eaa621906efa49789f42fe57c0469942ac62587307623876a638e` |
| App runner | `e088a994fccc9f04c7d64490d41e839c18f459f773de3b9c510f48851c04d37f` | `5040ee83caaf1119da19b844f41837f2edc09f2eb4684016ff509ee99384b3f2` |
| App AOT payload | `e433d70fe3b4c174e9932dc6beac3b448c714963a88c7a751fd957ae3394b84d` | `e433d70fe3b4c174e9932dc6beac3b448c714963a88c7a751fd957ae3394b84d` |
| CLI executable | `52620b3c4c8ef5a6f51ff292e96747de8320b4cdeb5eb66120387ce52f6c62ed` | `0ae5e860924e7d348f5f2c3b6b18327c5bb8d4dca727330a4afdce08ee9ee7c8` |

- App `Contents/MacOS/Meshchan` differs in 64 code signature bytes and 14 symbol string table bytes.
- CLI `bin/meshctl` differs in 96 code signature bytes and six symbol string table bytes.

The reference CLI passed eight offline storage checks and loaded the bundled
SQLite after relocation. The original App completed VM write, read and relocated
read with SQLite loaded from each respective bundle, successful exit and absent
PIDs. The isolated CLI and App serial replacement copies used the synthetic
empty-port library. The VM App quit normally. No physical devices were used.

Material collection and independent strict verification passed with
331 listed files and no open gates. The collector verified the receipt,
independently derived the SDK GN source closure, and delivered the
corresponding-source archive with the Release entry, guide and VM harness. The
final frozen check repeated strict verification. Comparison and operation logs
are in the retained checkout under `build/phase-1e4/pre-pr-validation/`.

Local pre-PR tests passed for 334 Python tool tests, 262 Flutter App tests,
362 shared core tests, 207 protocol tests and 287 CLI tests. Workspace analysis
and five diagnostic process scenarios passed. The initial diagnostic process
attempt selected Homebrew Clang and failed to link `System`. The same tests
passed in a fresh fixture with Apple Clang first on the child `PATH`. The frozen
Release builder independently recorded its controlled Apple toolchain. The
[branch CI run](https://github.com/007pig/meshchan/actions/runs/44747988036)
passed its Linux and macOS jobs on the frozen source commit.

These files are local ad hoc build products. Preserve their recorded bytes for
1E.5 staging. Rebind the final package, signatures and materials to the staged
artifacts when later steps change those bytes. Formal distribution signing,
DMG installation and upgrade, older macOS and Intel runtime, and hardware
validation remain separate release steps.

## Historical recipe 22 handoff

Recipe 22 selected **`build/phase-1e4/frozen-recipe-22/build/phase-1e4/run-048/`** from clean
local freeze commit `5ca73c2ec309c470938a91f5a395a5e0f64edc95`, with PR #41
merge commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80` as its parent.
App `0.1.0-rc.1+8` uses Apple short version `0.1.0` and build `8`.
CLI remains `0.1.0-rc.1`. Build, independent product verification and strict
materials passed. Comparison run `run-049` passed independent product checks
with materials status NOT_RUN.

| Exact run-048 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `f677a1a6e2ae53d0b9884ebd048c5d204ede510a5eeb7823b67e10b433eaa2bb` |
| `evidence/candidate-inventories.json` | `b64d778c8030f2722d55a2852f8d9d2b4c72cece0b12a3b64dd384566ff72c78` |
| `evidence/build-receipt.json` | `18b28fa7269e28396a50d3d563382b4fcbf89307335b4c88aeb43240f030b4bf` |
| `evidence/product-checks.json` | `a97a4a6d8941fe0634badf37b163a8563ffb69e8f3ba6e3d2063a3ed3d723987` |
| `evidence/prebuild-identities.json` | `e107d48b02d1714c4ed9573d28c124a18e9ec1d0726f2c88f329eb06741d45e5` |
| `materials/materials-manifest.json` | `0f0f37476dc36c916d071916ee14a5978ec4c6570c4cadb4f577bea1b4296861` |

From the retained checkout, the pre-staging check passed with this command.

```sh
cd build/phase-1e4/frozen-recipe-22
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-048 --require-frozen
```

The exact commit and its history were restored from
`build/phase-1e4/review-engine-runpath-stamp/phase-1e4-source.bundle`, SHA-256
`26b27b2c1f0354f8e9c5b1b1067b10c2d5fb4b54d59837b4044d3dc598daf8ac`.
Keep the retained checkout and run at their recorded paths for verification.

Strict materials verification covered 276 entries with no open gates.
The manifest's complete 403-entry source map matched the
original build receipt's prebuild record. The corresponding-source archive
contained the builder, required release guide, helpers, tests and root
`.gitignore`. The archived product report and resolved dependency graph
matched the originals. See `build/phase-1e4/frozen-recipe-22/build/phase-1e4/review-evidence/source-archive-check.log`
and `build/phase-1e4/frozen-recipe-22/build/phase-1e4/review-evidence/run-048-final-check.log`.
These results identify the exact App, CLI, and materials validated for recipe 22.

## Recipe 22 review verification

The validator checks the Mac App's manifest using the engine's runpaths first,
then the Runner's runpaths, as dyld does for `dlopen`. The older App in
`run-046` was rejected by the revised validator because the engine had a
host-dependent runpath before its bundled targets. Removing the factory
`/usr/local/lib/.` runpath on an isolated App copy, then resealing with
the existing local ad hoc metadata, passed static validation of both SQLite
and serial mappings for arm64 and x86_64. The engine's file-backed Mach-O
sections matched the original for both slices. The same change is a logged
step in recipe 22 and is the reason for the new App build.
See `build/phase-1e4/review-engine-runpath-stamp/real-app-loader-fixture.log`.

Flutter updates the checkout's `.dart_tool/version` in place. The builder
requires a single-link regular file whenever that stamp exists, alongside
the package config and graph. Tests cover a symlink, hard link, dangling
symlink and directory at the stamp path. The build stops before Pub and
leaves the external fixture intact. Loader tests also cover the engine's
higher-priority runpaths, including a conflicting bundled location.

Both invocations ran from the retained checkout using new output directories.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-048
/opt/homebrew/bin/python3 tool/build_release.py build --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-049
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-049
```

The reference materials command used the candidate-specific replacement
evidence at `run-048/validation/serial-rebuild.json`. The full invocation is
in `build/phase-1e4/frozen-recipe-22/build/phase-1e4/review-evidence/check-reference.sh`.
The collection and independent strict check logs are bound by
`run-048/build-info.json`.

The runs used macOS 27.2.1 arm64, Python 3.15.2, Flutter 3.50.0, bundled
Dart 3.14.0, Xcode 27.2 (27B52), Apple Clang 21 and macOS SDK 27.2. The
two builds recorded the same 137 compilation inputs, with identical
before and after records for both compilers and build input SHA-256
`4c117790fc102826da1d7adb1dd43559a0c689b801a8119865831d5e1d783c1e`.
Toolchain, graph, version, source and normalized recipe matched. The built
framework lookup results matched.

The App inventories each contain 74 entries, and the CLI inventories each
contain six. The only differences were in the two main executables.

- `Contents/MacOS/Meshchan` differs in 64 code signature bytes and 14 symbol
  string table bytes.
- `bin/meshctl` differs in 96 code signature bytes and six symbol string table
  bytes.

File-backed Mach-O sections and the embedded CLI Dart AOT image matched.
The full comparison is in `build/phase-1e4/frozen-recipe-22/build/phase-1e4/review-evidence/comparison.json`.

On the host, the selected CLI passed eight offline SQLite operations and
reopened storage using the bundled SQLite after relocation. On the arm64 VM,
the selected App passed write, read and relocated read with the dyld trace
showing SQLite loaded from the respective App bundle and with normal exit
and process absence. The App and CLI replacement copies loaded the modified
serial library and returned the expected synthetic empty-port result. See
`build/phase-1e4/frozen-recipe-22/build/phase-1e4/run-048/validation/`.
Intel runtime, physical hardware, Developer ID, notarization and packaging
remain later validation.

The local Python suite passed 248 tests, including process ownership. The
Flutter diagnostic worker suite passed both tests, and the separate Dart
diagnostic process check passed five cases. The logs are in
`build/phase-1e4/review-engine-runpath-stamp/`.

## Recipe 21 handoff record

Recipe 21 selected **`build/phase-1e4/frozen-recipe-21/build/phase-1e4/run-046/`**.
It was built from the clean local freeze commit
`5e0e8af9c731784938e69522ac5783dea21bb3f6`.
The build, product, candidate-specific runtime and strict materials checks
passed. Comparison build `run-047` passed its independent check with
materials status NOT_RUN.

| Exact run-046 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `9f3fcb6b66bc144187aa78aa5512bf0e7d29cf7ed372b39e68bf1d1941416db1` |
| `evidence/candidate-inventories.json` | `8c18ec285b8134fccb81cf255fc92e26d2f1057f6f51f0afe08b0724f3518bbb` |
| `evidence/build-receipt.json` | `57733e632334366c99a8649be0edc2a052cda76c4bfd6e4884d96cab9475029e` |
| `evidence/product-checks.json` | `f481c248a5c01d6d73c2892d380d53fb821758f093e301a0fda9a6591bdde289` |
| `evidence/prebuild-identities.json` | `907dfbe881e6c7c25d967e122475cc568cf65fbcba13083d41b9ccf449f51a20` |
| `materials/materials-manifest.json` | `f9b7c254e20426128257e3b79c86c813de887138057b6f5cedf07144a670b67f` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-21
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-046 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-hook-provenance-assets/phase-1e4-source.bundle`, SHA-256
`ac9d59ea8dcc54e13420d01d1e97779205fb4f5f7dac90e289c78918c8a7689c`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The corresponding-source archive includes the builder, build and materials
helpers, tests, build guide and root `.gitignore`. The archived product
report and resolved graph matched the build evidence byte for byte.
See `build/phase-1e4/frozen-recipe-21/build/phase-1e4/review-evidence/source-archive-check.log`
and `build/phase-1e4/frozen-recipe-21/build/phase-1e4/review-evidence/run-046-final-check.log`.

This run retains its recipe 21 products and evidence. Recipe 22 supersedes
it for staging.

## Recipe 21 review verification

The retained checkout is detached at clean local freeze commit
`5e0e8af9c731784938e69522ac5783dea21bb3f6`, whose parent is the PR #41
merge commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. An independent
clone of the source bundle recovered the exact builder.

The builder checks the checkout-local native hook cache immediately before
both the CLI and App compilers. The regression tests blocked a cache root
alias before the CLI build and a nested alias introduced between the CLI
and App builds. Retained external fixture bytes remained unchanged.

Both material passes compare the manifest's complete source map against the
prebuild source record whose bytes are hashed in the original build receipt.
A fixture changed a README outside the compilation input set while keeping
the Git commit and candidate the same. Both material passes rejected the
changed source map even when the collector returned PASS. A replacement
prebuild record also failed its receipt digest check.

The App native asset manifest now requires the runner's exact target set
and the two reviewed asset IDs on each target. The fixture rejected an
additional ID pointing to an external library and an additional ID pointing
to an otherwise valid bundled library. It also rejected an unexpected
architecture map. The retained candidate had the expected inventory and
passed the updated native asset check for both slices.

Python 3.15.2 byte-compilation, `git diff --check`, and all 247 local tool
tests passed, including process ownership tests.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The local run used the following commands from the retained checkout.
The materials command used the candidate-specific reference probe.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-046
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-047
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-047
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-046 \
  --downloads /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3/downloads \
  --probe build/phase-1e4/run-046/validation/serial-rebuild.json \
  --sdk-source-workspace /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-source
```

Two real engineering builds in an independent restored checkout rejected
an aliased hook cache root and an aliased child directory. Neither
compiler started, and the external fixture retained its sole file and
original bytes. See
`build/phase-1e4/review-hook-provenance-assets/hook-cache-negative-audit.log`.

The reference CLI passed eight offline SQLite operations. A complete copy
moved to `staging/meshctl relocated` matched its original inventory and
loaded its bundled SQLite library. The VM App passed write, read and
relocated read with normal shutdown. Both isolated replacement probes
loaded their replacement serial library and returned a synthetic empty-port
response. Evidence is under the reference run's `validation/` directory.

Both runs used macOS 27.2.1 arm64, Python 3.15.2, Flutter 3.50.0, bundled
Dart 3.14.0, Xcode 27.2 (27B52), Apple Clang 21.0.0 and macOS SDK 27.2.
They built App `0.1.0-rc.1+7` with Apple short version `0.1.0` and
build `7`, and CLI `0.1.0-rc.1`.

Both builds recorded the same 137 compilation inputs before and after
compilation, with SHA-256
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
Generated configuration, external sources, resolved dependencies, toolchain
and loader reports matched. The App inventories each have 74 entries, and
the CLI inventories each have six. The only differing files were the main
executables. The App runner differed in 64 signature bytes and 14 symbol
string table bytes. The CLI executable differed in 95 signature bytes and
six symbol string table bytes. Their file-backed Mach-O sections and the
embedded Dart AOT image matched. Comparison run `run-047` passed its independent
check with materials status NOT_RUN. See
`build/phase-1e4/frozen-recipe-21/build/phase-1e4/review-evidence/comparison.json`.

The reference materials manifest's complete 403-entry source map matched
the receipt-bound prebuild source map. The archived builder and guide
matched the frozen source bytes. See
`build/phase-1e4/frozen-recipe-21/build/phase-1e4/review-evidence/material-source-map-check.log`.

## Recipe 20 handoff record

Recipe 20 selected **`build/phase-1e4/frozen-recipe-20/build/phase-1e4/run-044/`**.
It was built from the clean local freeze commit
`bcee7422c33e2efdc97e52d078644d081eedeee6`.
The build, product, candidate-specific runtime and strict materials checks
passed. Comparison build `run-045` passed its independent check with
materials status NOT_RUN.

| Exact run-044 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `8d76f49f41552997a88c5ffabbeb4b9c3096b914a1938c48325c555ce5db2f78` |
| `evidence/candidate-inventories.json` | `06eb0e97bac0b016617dab613fec754a7f1abeacc222b870e5e526168b4138b9` |
| `evidence/build-receipt.json` | `d061bac3bc9af4d5e93934f1188709809d9a4d63b2689f20f836a8eaecbff37a` |
| `evidence/product-checks.json` | `75a938d36cb2528c949f54031673a5a232bc2675b0912bf1164686ec9c4d4c96` |
| `evidence/prebuild-identities.json` | `e5aa8226a522b8ab2e2dbf6dd418530434ea3aefccf6583f61960b2ee023f380` |
| `materials/materials-manifest.json` | `26e9a9e4e28949976bba9d996ca07abc4ffd7e3adc9d3928dd17e8e79f452753` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-20
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-044 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-bundle-isolation/phase-1e4-source.bundle`, SHA-256
`0ad753883794b2282c702ac4e6bb4a3885b6e1e14eac3c3a7f25f8e441f0b451`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The corresponding-source archive includes the builder, build and materials
helpers, tests, build guide and root `.gitignore`. The archived product
report and resolved graph matched the build evidence byte for byte.
See `build/phase-1e4/frozen-recipe-20/build/phase-1e4/review-evidence/source-archive-check.log`
and `build/phase-1e4/frozen-recipe-20/build/phase-1e4/review-evidence/run-044-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 20 review verification

The retained checkout is detached at clean local freeze commit
`bcee7422c33e2efdc97e52d078644d081eedeee6`, whose parent is the PR #41
merge commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. An independent
clone of the source bundle recovered the exact builder and SDK verifier.

For each Mach-O architecture, the validator rejects a requested or declared
`@rpath` install name that would map to more than one loaded bundled image.
A native arm64 fixture had two sibling libraries that resolved
`@rpath/leaf.dylib` to different files. dyld reused the first file and
reported the missing symbol from the second sibling, while the previous
validator reported both resolutions as successful. The updated validator
rejected the ambiguity before code ran. Tests also covered an explicit load
sharing the same install ID and two references to one actual file.
See `build/phase-1e4/review-bundle-isolation/native-fixture/`.

Material verification now requires a single-link regular file and real
parent directories for every manifest entry. Tests replaced a listed
license with a byte-identical symbolic link, hard link, or aliased parent
and observed rejection. The handoff check also rejected a substituted
payload while its manifest and logs remained bound.

The Flutter App cache and its parent directories are validated before
Flutter starts and before Xcode can write intermediates. Tests covered both
App cache directory aliases and a link appearing after Pub.

The SDK workspace lock coordinates distinct checkouts and the standalone
source tool. The collector holds it through the GN probe and evidence
copying. An independent process could not lock the workspace while a
report was being written and read under the lock, then acquired it after
release.

Python 3.15.2 byte-compilation, `git diff --check`, and all 245 local tool
tests passed, including process ownership tests.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The local run used the following commands from the retained checkout.
The materials command used the candidate-specific reference probe.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-044
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-045
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-045
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-044 \
  --downloads /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3/downloads \
  --probe build/phase-1e4/run-044/validation/serial-rebuild.json \
  --sdk-source-workspace /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-source
```

Two real engineering builds in an independent restored checkout rejected
aliases for the App's `.dart_tool` and `.dart_tool/flutter_build` directories
before starting Flutter. The external fixture retained its sole file and
original bytes. See
`build/phase-1e4/review-bundle-isolation/cache-negative-audit.log`.

The first VM preflight failed with an SSH timeout while UTM reported the
guest stopped. The maintainer started the guest. A fresh SSH identity check
confirmed the same authorized guest, and the product runner prepared a new
evidence directory. The first attempt remains under `review-evidence/vm/`
with its top-level preparation log. The retry uses `review-evidence/vm-retry/`.

The reference CLI passed eight offline SQLite operations. A complete copy
moved to `staging/meshctl relocated` matched its original inventory and loaded
its bundled SQLite library. After the VM restart, the App passed write, read
and relocated read with normal shutdown. Both isolated replacement probes
loaded their replacement serial library and returned a synthetic empty-port
response. Evidence is under the reference run's `validation/` directory.

Both runs used macOS 27.2.1 arm64, Python 3.15.2, Flutter 3.50.0, bundled Dart
3.14.0, Xcode 27.2 (27B52), Apple Clang 21.0.0 and macOS SDK 27.2. They built
App `0.1.0-rc.1+7` with Apple short version `0.1.0` and build `7`, and CLI
`0.1.0-rc.1`.

Both builds recorded the same 137 compilation inputs before and after
compilation, with SHA-256
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
Generated configuration, external sources, resolved dependencies, toolchain
and loader reports matched. The App inventories each have 74 entries, and
the CLI inventories each have six. The only differing files were the main
executables. The App runner differed in 64 signature bytes and 14 symbol
string table bytes. The CLI executable differed in 96 signature bytes and
six symbol string table bytes. Their file-backed Mach-O sections and the
embedded Dart AOT image matched. Comparison run `run-045` passed its independent
check with materials status NOT_RUN. See
`build/phase-1e4/frozen-recipe-20/build/phase-1e4/review-evidence/comparison.json`.

During the actual reference collection, an independent process also observed
that the collector held the SDK workspace lock. See
`build/phase-1e4/review-bundle-isolation/live-sdk-workspace-lock.log`.

## Recipe 19 handoff record

Recipe 19 selected **`build/phase-1e4/frozen-recipe-19/build/phase-1e4/run-042/`**.
It was built from the clean local freeze commit
`1e020f6e638cbd599ca1f547af6a254f1646b856`.
The build, product, candidate-specific runtime and strict materials checks
passed. Comparison build `run-043` passed its independent check with
materials status NOT_RUN.

| Exact run-042 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `bd02f499104b3e200d1e544422717df92c1d4130f693fc0eca9f2acb47e5e281` |
| `evidence/candidate-inventories.json` | `95eb7e67ddc227229cb91f18e42d9c9b4f89f76572258e0986f0a5b094cd5f83` |
| `evidence/build-receipt.json` | `a2ee4c108034fa048f47ea8d01245a84b4b4858d09799f7a3886a33a5aeed47f` |
| `evidence/product-checks.json` | `accdb3776f1ca03c7128e12b0997c6af7144f3130f187f4badbe40af20bb3d38` |
| `evidence/prebuild-identities.json` | `77b2dfb388bf60da531017d56fcef26a7f180c0c8c01302930e3fe7038ebde33` |
| `materials/materials-manifest.json` | `e61bcbfe1060ececff2c6bf833db201e8bb3641b891ff492ecf0e2b8b5b2cc40` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-19
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-042 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-pub-metadata-load-chain/phase-1e4-source.bundle`, SHA-256
`d1fd9866c86232dd7181dbb7598430534dde7df0798cab25bd0f896960a38f16`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The corresponding-source archive includes the builder, build and materials
helpers, tests, build guide and root `.gitignore`. The archived product
report and resolved graph matched the build evidence byte for byte.
See `build/phase-1e4/frozen-recipe-19/build/phase-1e4/review-evidence/source-archive-check.log`
and `build/phase-1e4/frozen-recipe-19/build/phase-1e4/review-evidence/run-042-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 19 review verification

The retained checkout is detached at clean local freeze commit
`1e020f6e638cbd599ca1f547af6a254f1646b856`, whose parent is the PR #41
merge commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. An independent
clone of the source bundle recovered the exact commit and builder.

The builder checks that any existing checkout-local package configuration
and graph are single-link regular files before starting Pub. It repeats
the checks before Flutter configuration and while recording its snapshot.
Unit tests cover symbolic links, dangling links, hard links, directory
entries, and an alias introduced after resolution.

The Mach-O inspection follows the linked dependency graph independently
for each slice. The report records the search order and declaring image
for each runpath. It preserves raw filesystem lookup and rejects
host-dependent fallback. Images outside the launcher's linked graph use
the launcher as the fallback context. Runtime validation still checks
the candidate's actual native assets.

A native macOS fixture installed different functions under the same
dependent library name. With both copies present, the old validator
reported the executable's fallback while dyld loaded the intermediate
loader's copy and returned 17. With the fallback removed, dyld still
returned 17 and the old validator failed. The updated validator selected
the intermediate loader's library in both cases. A synthetic test also
covered a runpath chain with a cyclic dependency. See
`build/phase-1e4/review-pub-metadata-load-chain/native-fixture/`.

Python 3.15.2 byte-compilation, `git diff --check`, and all 240 local tool
tests passed, including process ownership tests.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The local run used the following commands from the retained checkout.
The materials command used the candidate-specific reference probe.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-042
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-043
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-043
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-042 \
  --downloads /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3/downloads \
  --probe build/phase-1e4/run-042/validation/serial-rebuild.json \
  --sdk-source-workspace /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-source
```

In a separate restored checkout, two real engineering build attempts
each encountered a hard link to an owned external metadata fixture.
Both stopped before the `locked-resolution` command. SHA-256 comparison
confirmed that the fixture configuration and graph retained their bytes.
See `build/phase-1e4/review-pub-metadata-load-chain/metadata-negative-audit.log`.

The reference CLI passed eight offline SQLite operations. A complete copy
moved to `staging/meshctl relocated` matched its original inventory and
loaded its bundled SQLite library. The VM App passed write, read and relocated
read with normal shutdown. Both isolated replacement probes loaded their
replacement serial library and returned a synthetic empty-port response.
Evidence is under the reference run's `validation/` directory.

Both runs used macOS 27.2.1 arm64, Python 3.15.2, Flutter 3.50.0, bundled
Dart 3.14.0, Xcode 27.2 (27B52), Apple Clang 21.0.0 and macOS SDK 27.2.
They built App `0.1.0-rc.1+7` with Apple short version `0.1.0` and
build `7`, and CLI `0.1.0-rc.1`.

Both builds recorded the same 137 compilation inputs before and after
compilation, with SHA-256
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
Generated configuration, external sources, resolved dependencies,
toolchain and loader reports matched. The App inventories each have 74
entries, and the CLI inventories each have six. The only differing files
were the main executables. The App runner differed in 64 signature bytes
and 14 symbol string table bytes. The CLI executable differed in 96
signature bytes and six symbol string table bytes. Their file-backed
Mach-O sections and the embedded Dart AOT image matched. Comparison run
`run-043` passed its independent check with materials status NOT_RUN. See
`build/phase-1e4/frozen-recipe-19/build/phase-1e4/review-evidence/comparison.json`.

## Recipe 18 handoff record

Recipe 18 selected **`build/phase-1e4/frozen-recipe-18/build/phase-1e4/run-040/`**.
It was built from the clean local freeze commit
`3a777e67fe67402c4eba2f41a67a25122cc29cd2`.
The build, product, candidate-specific runtime and strict materials checks
passed. Comparison build `run-041` passed its independent check with
materials status NOT_RUN.

| Exact run-040 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `72745d890db21c5be1f22fbb7c2db0e7193f5a2941100bf4417314f18b4a7da1` |
| `evidence/candidate-inventories.json` | `2cb3fc13025213323e381bdc56a2e7f3ae4f783716aeb24dbbe76cbb2ecb94e2` |
| `evidence/build-receipt.json` | `d3598ced11834dbe153c0740af807b1d0e5d17c3f532ccb5d4463d84843fe385` |
| `evidence/product-checks.json` | `44d8a79e569a475ddf15dafab9fc3034f3e5b66fb5b78bd2bab51511271880c2` |
| `evidence/prebuild-identities.json` | `537dd57790b724cd157ccc0244dde3aadefae51c094fe96e7b522f06c825d7e9` |
| `materials/materials-manifest.json` | `ba68eae14be79909475bcaf25f916a7ac75b35122df6c3604a31ccf3975950c5` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-18
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-040 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-sdk-notices-lock-loader/phase-1e4-source.bundle`, SHA-256
`319568cf3d137dd3ae289bf271d96d9ff81707e260d46df41d3b42b84b7f18c4`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The corresponding-source archive includes the builder, build and materials
helpers, tests, build guide and root `.gitignore`. The archived product
report and resolved graph matched the build evidence byte for byte.
See `build/phase-1e4/frozen-recipe-18/build/phase-1e4/review-evidence/source-archive-check.log`
and `build/phase-1e4/frozen-recipe-18/build/phase-1e4/review-evidence/run-040-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 18 review verification

The retained checkout is detached at clean local freeze commit
`3a777e67fe67402c4eba2f41a67a25122cc29cd2`, whose parent is the PR #41
merge commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. An independent
clone of the source bundle recovered the exact commit and builder.

The external input snapshot now captures the actual SDK notice file
resolved for each SDK package. A fixture verified that changing the cached
license changes the snapshot, that an added `NOTICES` takes precedence
over `LICENSE`, and that removal of both files drops the record. The
retained App dependency list identifies the cached `sky_engine/LICENSE`
and Flutter framework `LICENSE` as the SDK notice inputs.

The shared lock opens `.dart_tool` without following directory links or
accepting a linked lock file. A real engineering build in a separate
checkout rejected an aliased `.dart_tool` before acquiring the lock.
Both package metadata fixtures in the target retained their original
bytes and no lock file was created there. Unit tests also cover a dangling
directory alias and symbolic and hard-linked lock files.

Loader verification preserves the raw path for the filesystem check, then
normalizes the selected file for the inventory lookup. The regression
tests reject trailing slash and dot components after a regular file under
`@loader_path`, `@executable_path` and `@rpath`. A live dyld probe using
the retained CLI's SQLite dylib rejected paths ending in `/` or `/.`
and loaded SQLite 3.54.1 through the normal path.
See `build/phase-1e4/review-sdk-notices-lock-loader/raw-dyld-check.log`.

Python 3.15.2 byte-compilation, `git diff --check`, and all 238 local tool
tests passed, including process ownership checks.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The local run used the following commands from the retained checkout.
The materials command used the candidate-specific reference probe.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-040
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-041
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-041
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-040 \
  --downloads /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3/downloads \
  --probe build/phase-1e4/run-040/validation/serial-rebuild.json \
  --sdk-source-workspace /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-source
```

The new App's `FlutterInputs.xcfilelist` names exactly the SDK notice paths
in the receipt-bound external source snapshot. The cached `sky_engine`
license SHA-256 is
`0d5050142d6b4605704d8844fcd5656ac23e718cf8f7d1e41149950da5edb4ef`.
The framework license SHA-256 is
`a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20`.
See `build/phase-1e4/frozen-recipe-18/build/phase-1e4/review-evidence/sdk-notices-check.log`.

The reference CLI passed eight offline SQLite operations. A complete copy
moved to `staging/meshctl relocated` matched its original inventory and
loaded its bundled SQLite library. The VM App passed write, read and relocated
read with normal shutdown. Both isolated replacement probes loaded their
replacement serial library and returned a synthetic empty-port response.
Evidence is under the reference run's `validation/` directory.

Both runs used macOS 27.2.1 arm64, Python 3.15.2, Flutter 3.50.0, bundled
Dart 3.14.0, Xcode 27.2 (27B52), Apple Clang 21.0.0 and macOS SDK 27.2.
They built App `0.1.0-rc.1+7` with Apple short version `0.1.0` and
build `7`, and CLI `0.1.0-rc.1`.

Both builds recorded the same 137 compilation inputs before and after
compilation, with SHA-256
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
Generated configuration, external package and SDK notice identities,
resolved dependencies, toolchain and loader reports matched. The App
inventories each have 74 entries, and the CLI inventories each have six.
The only differing files were the main executables. The App runner
differed in 64 signature bytes and 14 symbol string table bytes. The CLI
executable differed in 96 signature bytes and six symbol string table
bytes. Their file-backed Mach-O sections and the embedded Dart AOT
image matched. Comparison run `run-041` passed its independent check
with materials status NOT_RUN. See
`build/phase-1e4/frozen-recipe-18/build/phase-1e4/review-evidence/comparison.json`.

## Recipe 17 handoff record

Recipe 17 selected **`build/phase-1e4/frozen-recipe-17-final/build/phase-1e4/run-038/`**.
It was built from the clean local freeze commit
`9b90b5ec1a3488ac97e4431e0fc2d354209cd307`.
The build, product, candidate-specific runtime and strict materials checks
passed. Comparison build `run-039` passed its independent check with
materials status NOT_RUN.

| Exact run-038 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `5a0d0ab75a1472dfbc06886f3f1f10b96f0b594a07310e84bf7169c265cb5903` |
| `evidence/candidate-inventories.json` | `0c92d6e7c28462064daaad9faa211a1c4fd90cb3a18548b5525469083eb87f66` |
| `evidence/build-receipt.json` | `a7515e6930bef72d8de527e2ee6e00cbdbebbbdd5ef252b56cfc04db11eb14bb` |
| `evidence/product-checks.json` | `0b05aef355d00999baeeee4b99ea518a297d567dd0e3eda0573cc148ceea9282` |
| `evidence/prebuild-identities.json` | `5f53ee68c63158dba710df8ff310b36d6047319e0709438e3cb9463a866bc963` |
| `materials/materials-manifest.json` | `f5851016833493f35f946e9cc86608874a0f737f24c2f5b588d728ebf4ed20cd` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-17-final
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-038 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-flutter-outputs-shaders-loader/phase-1e4-source-final.bundle`, SHA-256
`7351a5fd0e7bfe60e663329d4ab11f31055acb4b116cca38a83865f71dbfc43b`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The corresponding-source archive includes the builder, build and materials
helpers, tests, build guide and root `.gitignore`. The archived product
report and resolved graph matched the build evidence byte for byte.
See `build/phase-1e4/frozen-recipe-17-final/build/phase-1e4/review-evidence/source-archive-check.log`
and `build/phase-1e4/frozen-recipe-17-final/build/phase-1e4/review-evidence/run-038-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 17 review verification

The retained checkout is detached at clean local freeze commit
`9b90b5ec1a3488ac97e4431e0fc2d354209cd307`, whose parent is the PR #41
merge commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. An independent
clone of the source bundle recovered the exact commit and builder.

The builder validates the macOS generated configuration tree before Flutter
starts and again after dependency resolution, before configuration. It rejects
symbolic links, hard-linked files and special entries, and checks the same
paths when taking or reading a configuration snapshot. A separate clean
checkout with an ignored symbolic link for `flutter_export_environment.sh`
failed before invoking Flutter. The link's external fixture retained its
bytes and mode. Synthetic tests also covered a dangling link, a hard link,
a directory alias and an alias appearing after dependency resolution.

The SDK snapshot hashes `impellerc` and inventories its `shader_lib` tree.
A fixture changed the compiler, the Flutter runtime effect header and an
Impeller include independently and observed changed toolchain identities.
Missing compiler and runtime effect inputs failed preflight.

The loader rejects an absolute host fallback reached before the bundled file,
even when the build Mac has no library there. A fixture tested the Flutter
factory path both before and after the bundled runpath and with the bundled
candidate missing. It also tested Xcode's system-owned `/usr/lib/swift`
path with a matching candidate absent and then present in the dyld cache.
The real App uses that Xcode runpath. The App and CLI loader and App FFI
checks passed against the retained recipe 16 products without changing them.

Python 3.15.2 byte-compilation, `git diff --check`, and all 236 local tool
tests passed, including process ownership tests.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The local run used the following commands from the retained checkout.
The materials command used the candidate-specific reference probe.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-038
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-039
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-039
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-038 \
  --downloads /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3/downloads \
  --probe build/phase-1e4/run-038/validation/serial-rebuild.json \
  --sdk-source-workspace /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-source
```

The reference before-build record contains 25 shader include inventory
entries. Its `impellerc` digest is
`dee8bfaa9378106ac3b0b314b227fc15a859c743735f6638b057db6651ff05a4` and its
`flutter/runtime_effect.glsl` digest is
`a03472b0d701dbeb3b81a53aca85127cfa1bc89cfb2165c18fdc6d6463a72b48`.
An independent invocation of the same cached compiler with the pinned
Flutter shader source produced byte-for-byte the shipped `stretch_effect.frag`.
The compiler's dependency file lists the recorded runtime effect header.
See `build/phase-1e4/frozen-recipe-17-final/build/phase-1e4/review-evidence/shader-inputs-check.log`.

The reference CLI passed eight offline SQLite operations. A complete copy
moved to `staging/meshctl relocated` matched its original inventory and
loaded its bundled SQLite library. The VM App passed write, read and relocated
read with normal shutdown. Both isolated replacement probes loaded their
replacement serial library and returned a synthetic empty-port response.
Evidence is under the reference run's `validation/` directory.

Both runs used macOS 27.2.1 arm64, Python 3.15.2, Flutter 3.50.0, bundled
Dart 3.14.0, Xcode 27.2 (27B52), Apple Clang 21.0.0 and macOS SDK 27.2.
They build App `0.1.0-rc.1+7` with Apple short version `0.1.0` and
build `7`, and CLI `0.1.0-rc.1`.

The before and after maps for both runs contain the same 137 compilation
inputs, with SHA-256
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
The toolchain, generated configuration, resolved dependencies, build recipe
and loader reports matched. The App inventories each have 74 entries and
the CLI inventories each have six, with matching composition. The only
differing files were the main executables. The App runner differed in 64
signature bytes and 14 symbol string table bytes. The CLI executable differed
in 96 signature bytes and five symbol string table bytes. Their file-backed
Mach-O sections, including the embedded Dart AOT image, matched.
Comparison run `run-039` passed its independent check with materials
status NOT_RUN. See
`build/phase-1e4/frozen-recipe-17-final/build/phase-1e4/review-evidence/comparison.json`.

## Recipe 16 handoff record

Recipe 16 selected **`build/phase-1e4/frozen-recipe-16-final/build/phase-1e4/run-036/`**.
It was built from the clean local freeze commit
`e890fc4b54f460048239bf11d0128f427fefe7a2`.
The build, product, candidate-specific runtime and strict materials checks
passed. Comparison build `run-037` passed its independent check with
materials status NOT_RUN.

| Exact run-036 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `e368a45fb67ac9a50f894ddc56e80ed6546dd36a02b843badca3df3fb624a535` |
| `evidence/candidate-inventories.json` | `84c715d0993df7cdebce87705e5fa0b32d71829bbb0cf61b98d7693d9c50cc0f` |
| `evidence/build-receipt.json` | `6f1153c8d355d822056f2ccef069ad15dbee66890965f92c9391b67bc53aaf33` |
| `evidence/product-checks.json` | `74e659dd85daa7684f98ffa723cdd2dac28dfa9cb312c2a6510c9cac9c71d9cf` |
| `evidence/prebuild-identities.json` | `26d37867fffc6d2d218b5452a98d3f50130be53317cbf59c80abe0ae804bcc8a` |
| `materials/materials-manifest.json` | `43bc52011dcb166f1d9eb6caf54f5ef804e72b4785bcfb793369e402e36c45f3` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-16-final
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-036 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-sdk-receipt/phase-1e4-source-final.bundle`, SHA-256
`d0fe3fff37042abcdca5762708bb403da0af0cf62cf1e9d656f6dfb190d97f2f`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The corresponding-source archive includes the builder, build and materials
helpers, tests, build guide and root `.gitignore`. The archived product
report and resolved graph matched the build evidence byte for byte.
See `build/phase-1e4/frozen-recipe-16-final/build/phase-1e4/review-evidence/source-archive-check.log`
and `build/phase-1e4/frozen-recipe-16-final/build/phase-1e4/review-evidence/run-036-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 16 review verification

The retained checkout is detached at clean local freeze commit
`e890fc4b54f460048239bf11d0128f427fefe7a2`, whose parent is the PR #41
merge commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. An independent
clone of the source bundle recovered the exact commit, builder and
materials checker.

The before-build, after-build and independent live checks now hash the
bundled `dartvm` and inventory the cached Release FlutterMacOS framework
that Flutter copies for Xcode. The inventory records the actual headers,
module map, engine and symlink targets. A fixture changed each of the
Dart VM executable, primary and secondary headers, module map, engine,
and framework link independently. Each change altered the toolchain
identity. Missing `dartvm` and module-map fixtures failed preflight.

The standalone materials receipt verifier requires the inventory, resolved
dependency graph and product report for recipe 9 and later. Removing each
binding or altering its companion file failed the synthetic verification.
Changing a directory mode while leaving regular-file bytes intact also
failed. The actual retained 1E.3 format-1 receipt, recipe 8 receipt with
inventory and graph, and recipe 15 receipt all passed the updated verifier.
See `build/phase-1e4/review-sdk-receipt/historical-receipts.log`.

Python 3.15.2 byte-compilation, `git diff --check`, and all 234 local
tool tests passed, including process ownership.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The preliminary attempt `run-034` was canceled after identifying recipe 8's
historical contract. Its builder reaped its owned children and recorded
`FAIL` with the cancellation. The accepted runs use new directories and
the same final frozen commit.

A live process probe confirmed that the bundled Dart launcher executed
`bin/dartvm`. The reference receipt recorded its SHA-256 as
`80a653f55cb0e6f8b81b2785a286ddb45c952f5e4f32ad214478db98b8d8bf0d`.
The Release framework snapshot contains 33 entries. All 15 headers and the
module map copied into Xcode's build-products directory matched their recorded
SDK hashes. See `build/phase-1e4/review-sdk-receipt/live-dart-vm.log` and
`build/phase-1e4/frozen-recipe-16-final/build/phase-1e4/review-evidence/sdk-inputs-check.log`.

The local run used these commands from the retained checkout. The materials
command used the reference run's candidate-specific replacement probe.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-036
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-037
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-037
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-036 \
  --downloads /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3/downloads \
  --probe build/phase-1e4/run-036/validation/serial-rebuild.json \
  --sdk-source-workspace /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-source
```

The reference CLI passed eight offline SQLite operations. A complete copy
moved to `staging/meshctl relocated` matched its original inventory,
passed signature and loader checks, and loaded its own SQLite library.
The App write, read and relocated read passed inside the macOS VM with
normal shutdown. Candidate-bound replacement probes observed the
replacement serial library in both isolated product copies using a
synthetic empty-port response. The original products and their run
inventories were preserved.

The standalone receipt verifier accepted the actual recipe 16 receipt and
all companions. Separate temporary copies of that receipt with each new
required digest removed were rejected. See `review-evidence/receipt-binding-check.log`
under the frozen checkout's `build/phase-1e4/`.

Both runs used macOS 27.2.1 arm64, Python 3.15.2, Flutter 3.50.0, bundled
Dart 3.14.0, Xcode 27.2 (27B52), Apple Clang 21.0.0 and macOS SDK 27.2.
They produced App `0.1.0-rc.1+7` with Apple short version `0.1.0` and
build `7`, and CLI `0.1.0-rc.1`.

The before and after maps for both runs contain the same 137 compilation
inputs, with SHA-256
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
The toolchain, generated configuration, resolved dependencies and build
recipe matched. App inventories each have 74 entries and CLI inventories
each have six entries with matching composition. The only differing files
were the main executables. The App runner differed in 64 signature bytes
and 14 symbol string table bytes. The CLI executable differed in 95
signature bytes and five symbol string table bytes. The file-backed
Mach-O sections, including the embedded Dart AOT image, matched.
Comparison run `run-037` passed its independent check with materials
status NOT_RUN. See
`build/phase-1e4/frozen-recipe-16-final/build/phase-1e4/review-evidence/comparison.json`.

## Recipe 15 handoff record

Recipe 15 selected **`build/phase-1e4/frozen-recipe-15/build/phase-1e4/run-032/`**.
It was built from the clean local freeze commit
`02ed7735adbafc291f4d45a740af25fcb3dfb246`.
The build, product, candidate-specific runtime and strict materials checks
passed. Comparison build `run-033` passed its independent check with
materials status NOT_RUN.

| Exact run-032 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `05dad6783fbb92318230e8f754fe9e035bc5dc67cfe3acb2626a533fa7d50642` |
| `evidence/candidate-inventories.json` | `3e0d22bcd5567cdfcb25aa54f556406b097af879b0171fd34dd2c24993220ffc` |
| `evidence/build-receipt.json` | `0d5b3c7d94ea06f4325f628dceb35a0be416e3ab079429a1060ae52222b259a0` |
| `evidence/product-checks.json` | `89bfb0c6493cb41912ee427908d424b6c60d9bdee9eac1e364a1547865a738b2` |
| `evidence/prebuild-identities.json` | `c4923bb9ab99c94c5f17cd900271ba7a4ad0cd2efa65fb42262d85b2bf98ebe0` |
| `materials/materials-manifest.json` | `8cb1b3725de006ea647df5494222cbc40bd4dd8d9ff3be8ca1c5758a83801579` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-15
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-032 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-relocatable-loader/phase-1e4-source.bundle`, SHA-256
`34dc8cdba0da67f61d759e7ddcc76e28cfe2492387cbe8aeaf6653eb20f6f0f8`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The corresponding-source archive includes the builder, build and materials
helpers, tests, build guide and root `.gitignore`. The archived product
report and resolved graph matched the build evidence byte for byte.
See `build/phase-1e4/frozen-recipe-15/build/phase-1e4/review-evidence/source-archive-check.log`
and `build/phase-1e4/frozen-recipe-15/build/phase-1e4/review-evidence/run-032-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 15 review verification

The retained clean checkout is detached at local freeze commit
`02ed7735adbafc291f4d45a740af25fcb3dfb246`, whose parent is the PR #41 merge
commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. A fresh clone of the source
bundle recovered the exact commit and builder.

A real `git replace` fixture reproduced the original false-clean state.
The uncontrolled checkout read the replacement tree while retaining the
original HEAD ID. The controlled source and SDK probes rejected the changed
tree. The recorded child environment disables replacement objects.

The SDK fingerprint covers the cached source Material Icons font as well as
the subsetter. Changes to either fixture input changed the toolchain identity
and a missing input failed preflight.

The loader fixtures reject a runpath, direct dependency, `@rpath` dependency,
and symlink traversal that leave and re-enter the bundle. The original
recipe 14 CLI carried a dormant out-of-bundle `@loader_path/../../..` runpath
inherited from Dart. The updated validator rejected it. On an isolated
copy, removing that runpath and restoring the local ad hoc signature passed
strict codesign, version, loader and SQLite checks from a renamed directory.
Its file-backed Dart SDK runtime sections still matched the installed
`dartaotruntime` sections. The original App's loader and native asset checks
passed without editing it.

Python 3.15.2 byte-compilation, `git diff --check`, and all 234 local tool
tests passed, including process ownership tests.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The exact reference CLI passed eight offline SQLite operations. A complete
copy in `staging/meshctl relocated` matched the original inventory, passed
strict codesign and loader verification, and loaded its own
`lib/libsqlite3.dylib` for `settings show`. The App passed write, read and
relocated read in the VM with normal shutdown. Candidate-bound native
replacement probes observed the replacement serial library in isolated App
and CLI copies with a synthetic empty-port response. These checks used no
hardware. The run's `validation/` directory records these results.

The reference and comparison runs used macOS 27.2.1 arm64, Python 3.15.2,
Flutter 3.50.0, bundled Dart 3.14.0, Xcode 27.2 (27B52), Apple Clang 21.0.0,
and macOS SDK 27.2. Their App version is `0.1.0-rc.1+7` with Apple short
version `0.1.0` and build `7`. Their CLI version is `0.1.0-rc.1`. The
reference prebuild snapshot records the Material Icons source font
SHA-256 `d9865b671a09d683d13a863089d8825e0f61a37696ce5d7d448bc8023aa62453`.
The two CLI normalization commands succeeded and appear in the receipt.

Both runs recorded the same 137 compilation inputs before and after each
product build. The compilation input digest for both runs is
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
The comparison also matched the recipe, toolchain, generated configuration,
external sources, locked resolution and complete composition of the two
products. The App inventory has 74 entries and the CLI has six. Only the
two main executables differed. The App runner differed by 64 bytes in its
signature and 14 bytes in its symbol string table. The CLI executable
differed by 96 bytes in its signature and six bytes in its symbol string
table. File-backed Mach-O sections, including the embedded Dart AOT image,
matched. The independent check of `run-033` passed with materials status
NOT_RUN. The comparison and its per-file byte analysis are in
`build/phase-1e4/frozen-recipe-15/build/phase-1e4/review-evidence/comparison.json`.

The local run used the following commands from the retained checkout. The
materials command used the candidate-specific probe for the reference run.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-032
/opt/homebrew/bin/python3 tool/build_release.py build \
  --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-033
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-033
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-032 \
  --downloads /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3/downloads \
  --probe build/phase-1e4/run-032/validation/serial-rebuild.json \
  --sdk-source-workspace /Users/xiaoyu/Documents/my_projects/meshchan/build/phase-1e3-source
```

## Recipe 14 handoff record

Recipe 14 selected **`build/phase-1e4/frozen-recipe-14/build/phase-1e4/run-030/`**.
It was built from the clean local freeze commit
`f860763d5393f4b8a8cfebbf94127e5e1da98f62`.
The build, product, candidate-specific runtime and strict materials checks
passed. Comparison build `run-031` passed its independent check with
materials status NOT_RUN.

| Exact run-030 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `bea5d2804fa65afd03ac853422dfe7b5d9f881668b31a119e85d9cdecbd3529f` |
| `evidence/candidate-inventories.json` | `fe04bc13984cc2ea4ea7c3e9990cd3fd4402eea6b6d71f166a78d37bf5d844c1` |
| `evidence/build-receipt.json` | `3cf7769202ad5f10cd58b1b5da1631c73a031ef32eea013459335de3470d468d` |
| `evidence/product-checks.json` | `56807d3699b42aad663465935f3a70086fba7a600da032dd7c4a1bdfc23a1d31` |
| `evidence/prebuild-identities.json` | `cbca8eddad0809db6288118704e8d0e5afde34c08f57ca8356ecc18417d8db48` |
| `materials/materials-manifest.json` | `72c54d5893d6fbf36dcca0d6c4ad5c8c3183948ad7f4ebbbcfb8ddad7f4f3533` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-14
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-030 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-system-inputs/phase-1e4-source.bundle`, SHA-256
`7537769574269fb6e6340a283c4646cc9795c9681d77c76a8a7738cea4def36f`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The source archive contains the builder, materials helper, tests, build guide,
and root `.gitignore`. The archived product report records system library
availability. The frozen prebuild and material evidence record the icon
subsetter identity and the shipped font. See
`build/phase-1e4/frozen-recipe-14/build/phase-1e4/review-evidence/source-archive-check.log` and
`build/phase-1e4/frozen-recipe-14/build/phase-1e4/review-evidence/run-030-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 14 review verification

The retained clean checkout is detached at local freeze commit
`f860763d5393f4b8a8cfebbf94127e5e1da98f62`, whose parent is the PR #41 merge
commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. An independent clone of
the source bundle recovered the commit and the exact builder.

The product validator checks canonical system library paths against the
validation host's filesystem and dyld shared cache. A direct probe confirmed
that fileless AppKit and `libSystem.B.dylib` were in the cache and that an
invented path was absent. The loader tests rejected missing required,
upward, re-exported and lazy loads. They allowed and recorded an absent
weak load. A read-only check of the recipe 13 products verified 132 App
system-load entries and 11 CLI entries through the cache.

The SDK fingerprint now covers the actual macOS icon subsetter
`bin/cache/artifacts/engine/darwin-x64/font-subset`. A fixture changed its
bytes and changed the toolchain identity. Removing it failed preflight.

HEAD, source enumeration and ignore checks use the same controlled Git
environment. A fixture pointed `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE`
at another repository. The correct checkout passed against its own HEAD
and still rejected the prior commit, while source enumeration and output
ignore checks also used the correct checkout.

Python 3.15.2 byte-compilation and `git diff --check` passed. Local tool
discovery passed all 232 tests, including process ownership checks.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The actual prebuild identity recorded `font-subset` SHA-256
`2524e65f538c0bd7da59da48383557de079c4abfa59c2c52aacefbe6a2d49e90`.
The App shipped a 2,048-byte Material Icons font with SHA-256
`65666ba1a370938ce1c3668cea3559b9eb7197e6cb80c34322013ed528180188`.
The SDK source font was 1,645,184 bytes. All 143 App/CLI system load entries
in the reference product report resolved in the validation host's dyld cache.

The exact reference CLI passed eight offline SQLite operations. The App
passed write, read and relocated read in the VM with normal shutdown.
Candidate-bound native replacement probes observed the replacement serial
library in isolated App and CLI copies with a synthetic empty-port response.
The checks used no hardware.

Both builds used macOS 27.2.1 arm64, Flutter 3.50.0, bundled Dart 3.14.0,
Xcode 27.2 (27B52), Apple Clang 21.0.0, and macOS SDK 27.2. They produced
App `0.1.0-rc.1+7` with Apple short version `0.1.0` and build `7`, and CLI
`0.1.0-rc.1`, from a clean checkout.

Both before-after compilation snapshots identified 137 inputs and shared digest
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`. The
toolchain, generated configuration, dependency resolution, recipe, and complete
product composition matched. Their loader reports also matched. Differences
were limited to 64 signature bytes and 14 symbol-string-table bytes in the
App runner and 96 signature bytes and six symbol-string-table bytes in the
CLI executable. Their file-backed Mach-O sections, including the embedded Dart
AOT image, matched. The independent check of `run-031` passed with materials
status NOT_RUN.

The final pre-staging recheck was launched in the frozen checkout with
`GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` pointing to the development
checkout. An uncontrolled Git command in that context returned the development
HEAD. See `review-evidence/foreign-git-context.log` under the frozen checkout's
`build/phase-1e4/` for both commit values and the same directory's
`run-030-final-check.log` for the release result.

## Recipe 13 handoff record

Recipe 13 selected **`build/phase-1e4/frozen-recipe-13/build/phase-1e4/run-028/`**.
It was built from the clean local freeze commit
`a53bbdf716a217a7769557637fc1a882be5b3d7e`.
The build, product, candidate-specific runtime and strict materials checks
passed. Comparison build `run-029` passed its independent check with
materials status NOT_RUN.

| Exact run-028 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `36fbc6995c0cb7336d86263f85d2c0ae9813f6614128771c64755951822af0c9` |
| `evidence/candidate-inventories.json` | `dc78a56d7f1f40028fb6c28268495f8699a7c501cc280fb8790fa666cc1412d6` |
| `evidence/build-receipt.json` | `ad3f66b8082c826c283e7db2bc42af40a0c09546fde2c1eb8349b2b8cb48a943` |
| `evidence/product-checks.json` | `a5478290501f10a852ed83551ff3aed457edd5ea1427f127254e41976cb8da47` |
| `evidence/prebuild-identities.json` | `cf856328f9bc556d3af709d35ad21ce126636c93c6ece2a8c021bf456124f64b` |
| `materials/materials-manifest.json` | `04f4c42db28e9f9326da0483154cb61e3c80e80aa974fce7ad5ba8d40c3c0372` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-13
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-028 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-cli-storage/phase-1e4-source.bundle`, SHA-256
`a99d5922bc14c491e803ff1a8d2c3b187c42e62a2f6d8c559f466c2ca74397ac`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The corresponding-source archive contains the builder, tests, build guide,
and root `.gitignore`. The archived product report records the CLI's bundled
SQLite load and closed storage. The frozen prebuild evidence records the
CLI product kernel digest. See
`build/phase-1e4/frozen-recipe-13/build/phase-1e4/review-evidence/source-archive-check.log` and
`build/phase-1e4/frozen-recipe-13/build/phase-1e4/review-evidence/run-028-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 13 review verification

The retained clean checkout is detached at local freeze commit
`a53bbdf716a217a7769557637fc1a882be5b3d7e`, whose parent is the PR #41 merge
commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. A fresh clone of the source
bundle recovered that commit and the exact release builder.

The compiler input record now covers the bundled Dart SDK's
`lib/_internal/vm_platform_product.dill` along with the separate Release App
platform kernel. Replacing either fixture kernel changed the toolchain digest.
Removing either prevented the preflight.

The validator completes the bundle inventory, Mach-O loader checks and local
signature checks before starting the CLI. A symlink fixture pointing to a
real external executable was rejected before any probe. The signature tests
also verified that an invalid sibling dylib blocks product execution.

The CLI then opens storage with `settings show --json` and a temporary data
directory outside the bundles. The check requires a successful storage close
and a SQLite file header. The dyld trace must contain the exact bundled
`lib/libsqlite3.dylib`. On the previous candidate, the command succeeded and
dyld reported both the OS and bundled SQLite paths. The fixture verified that
system-only loads, lookalike paths and invalid database bytes fail. The
updated validator passed against the original recipe 12 products.

Python 3.15.2 byte-compilation and `git diff --check` passed. Local tool discovery
passed all 230 tests, including tests for ownership and timeout of the product
validator's subprocesses.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The reference prebuild record hashed the CLI product kernel as
`57dbd8eebcfbc5abe7f49ffba888683f9b14cbb400316c986ea32a59807ff809`.
The reference product report records `lib/libsqlite3.dylib` as the library
loaded by `settings show` and reports closed storage.

The exact reference CLI passed eight offline storage operations. The App
passed write, read and relocated read in the VM with normal shutdown.
Candidate-bound native replacement checks observed the replacement serial
library in isolated App and CLI copies with a synthetic empty-port response.
The checks used no hardware.

Both builds used macOS 27.2.1 arm64, Flutter 3.50.0, bundled Dart 3.14.0,
Xcode 27.2 (27B52), Apple Clang 21.0.0, and macOS SDK 27.2. They produced
App `0.1.0-rc.1+7` with Apple short version `0.1.0` and build `7`, and CLI
`0.1.0-rc.1`, from a clean checkout.

Both builds independently matched the 137-input before-after snapshots,
with digest `6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
Toolchain identities, including both product kernels, generated configuration,
dependency resolution, recipe and bundle composition matched. Inventories
listed 74 App and six CLI entries. Only the App runner (64 signature bytes
and 14 symbol-string-table bytes) and CLI executable (96 signature bytes
and six symbol-string-table bytes) differed. File-backed Mach-O sections,
including the CLI's embedded Dart AOT image, matched. Both CLI storage checks
reported the bundled SQLite library and closed storage. The independent
check of comparison run `run-029` passed with materials status NOT_RUN.

## Recipe 12 handoff record

Recipe 12 selected **`build/phase-1e4/frozen-recipe-12/build/phase-1e4/run-026/`**.
It was built from the clean local freeze commit
`a4def267e2fc472fa6fb70293c46743977f43f14`.
The build, product, candidate-specific runtime and strict materials checks
passed. The comparison build `run-027` passed its independent check with
materials status NOT_RUN.

| Exact run-026 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `deeab943ff2ddb20c90e77863d7794b46d7721005dade6e1c57920e73df0136c` |
| `evidence/candidate-inventories.json` | `c18d73f1651e9c3f414937cd315580005b2055c8f074f4045333bee0f506ee1b` |
| `evidence/build-receipt.json` | `67735973688e0538866d111c7d57250c1d884a8eb3b687abee974f627b94a498` |
| `evidence/product-checks.json` | `d85a2ed32353802fd53e459f675d026967bf46495e644187291ff2f079575ba4` |
| `evidence/prebuild-identities.json` | `058266b654271a0759de5d8d1754b083873aafb695759da3165fe07251781aeb` |
| `materials/materials-manifest.json` | `e40393c16f925d16dd1b3059bb32682ddbe9cf434d4cb567520b7e613c7ba926` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-12
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-026 --require-frozen
```

The frozen commit and its Git history can be recovered from
`build/phase-1e4/review-kernel-loader/phase-1e4-source.bundle`, SHA-256
`c45308f086e8239fc8b28386ea15164149bb35ff0910e58f3238d6bc5f0bbc74`.
Keep the checkout and products at their recorded paths.

Strict materials verification covered 276 entries with no open gates.
The source archive contains the builder, test, build guide, and root
`.gitignore`. The archived product report records the per-slice Mach-O
file types. The frozen prebuild evidence records the generated package graph
and cached Release platform kernel digests. See
`build/phase-1e4/frozen-recipe-12/build/phase-1e4/review-evidence/source-archive-check.log` and
`build/phase-1e4/frozen-recipe-12/build/phase-1e4/review-evidence/run-026-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 12 review verification

The retained clean checkout is detached at local freeze commit
`a4def267e2fc472fa6fb70293c46743977f43f14`, whose parent is the PR #41 merge
commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. A fresh clone of the
source bundle recovered the exact commit and builder.

The generated-configuration record now covers the Flutter-consumed
`.dart_tool/package_graph.json` in addition to package configuration and the
Swift package files. A fixture changed the generated graph after the initial
snapshot and the build failed before starting Xcode. The separate
`dart pub deps --json` output remains bound as dependency-resolution evidence.

The toolchain record covers the cached Release kernel
`flutter_patched_sdk_product/platform_strong.dill`. An SDK fixture verified
that replacing its bytes changes the toolchain identity and that removing it
fails the preflight.

The product validator rejects both byte orders of thin 32-bit Mach-O.
It records the Mach header file type for every inspected architecture.
The loader fixtures rejected executable and object-file targets, even with
the loading architecture present. The native asset fixture also rejected a
non-dylib FFI target. A read-only recheck of the recipe 11 bundles verified
real `MH_EXECUTE` (2) entry points and `MH_DYLIB` (6) library slices using
the updated validator.

All 228 tool tests passed with Python 3.15.2, including the process ownership
tests. Python byte-compilation and `git diff --check` also passed.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The reference build recorded these SHA-256 digests.

| Input | SHA-256 |
| --- | --- |
| `.dart_tool/package_graph.json` | `f9a31a51b91f86dab0ee54957ef468b825b40b52a966e8117ccda6fbab86f255` |
| Release `platform_strong.dill` | `486c68548ae6924145a12207ef5bb0ce1208a04c9c6ac3e6fb1b69b9f1f1507a` |

The exact reference CLI passed eight offline SQLite operations. The reference
App passed VM write, read and relocated read with normal shutdown. Native
replacement probes in complete isolated copies of both products loaded the
replacement library with a synthetic empty-port response. Both observations
were bound to the original candidate bytes. The checks used no hardware.
The product report recorded three executable slices and ten dylib slices.

Both builds used macOS 27.2.1 arm64, Flutter 3.50.0, bundled Dart 3.14.0,
Xcode 27.2 (27B52), Apple Clang 21.0.0, and macOS SDK 27.2. They produced
App `0.1.0-rc.1+7` with Apple short version `0.1.0` and build `7`, and
CLI `0.1.0-rc.1`, from a clean source checkout.

The before-after compilation snapshots for both runs contained 137 inputs
and shared SHA-256
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
The package graph, platform kernel, lockfile, dependency resolution, toolchain,
recipe, and product composition matched. Both inventories listed 74 App and
six CLI entries. Differences were restricted to 64 signature bytes and 14
symbol-string-table bytes in the App runner and 96 signature bytes and five
symbol-string-table bytes in the CLI executable. The file-backed Mach-O
sections, including those in the embedded Dart AOT image, matched.
The independent check of `run-027` passed with materials NOT_RUN.

The materials launcher reached its wait limit during the comparison check.
A second launcher invoked collection against the verified `run-026` products.

## Recipe 11 handoff record

Recipe 11 selected **`build/phase-1e4/frozen-recipe-11/build/phase-1e4/run-024/`**.
It was built from the clean local freeze commit
`5b7d79f8f07d6b21428124fdd3aafb106057842b`.
The build, product, candidate-specific runtime and strict materials checks
passed. The comparison build `run-025` passed its independent check with
materials status NOT_RUN.

| Exact run-024 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `4310f062295f37d5ed82c6cd4d89c88ae21fa77972a33e989eac3ca0df2a6ce2` |
| `evidence/candidate-inventories.json` | `5314829dbc359ad8c3b8fc0930fdedd182bf87213ad5ed6143f49da307be1dd8` |
| `evidence/build-receipt.json` | `1d8eba9794d1f07e15d939045828ed4ed3bccb330b73caf3cf693404d0613c70` |
| `evidence/product-checks.json` | `3e7212d4c9ffce997856171b871325b186b3243f3e1ad679cf834b7542319ad7` |
| `evidence/prebuild-identities.json` | `2b44c5dd4917ad40d47cc375c581b4c109f7487a6c435a918d0af466737bc004` |
| `materials/materials-manifest.json` | `b38babb40b0b8ca09479fe0f00296be7fe059c7083d36f673414211e4d2e3035` |

The pre-staging check passed with the retained checkout as its verification root.

```sh
cd build/phase-1e4/frozen-recipe-11
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-024 --require-frozen
```

The source commit and its Git history can be recovered from
`build/phase-1e4/review-generated-inputs/phase-1e4-source.bundle`, SHA-256
`9d5b5289616f8f2bd63d48fac189c778be0a9b944088242ee6d34d2dead4bdab`.
Keep the checkout and products at their recorded paths when the development
branch advances.

Strict materials verification covered 276 entries with no open gates.
The corresponding-source archive contains the release entry, test, build
guide, and root `.gitignore`. The material package includes the receipt-bound
product report and dependency graph. The generated Swift package snapshot
appears in `evidence/prebuild-identities.json`. See
`build/phase-1e4/frozen-recipe-11/build/phase-1e4/review-evidence/source-archive-check.log` and
`build/phase-1e4/frozen-recipe-11/build/phase-1e4/review-evidence/run-024-final-check.log`.

Stage the exact App and CLI bytes from this run. Rebind their product
identities and materials after applicable signing and packaging.

## Recipe 11 review verification

The reviewed source was frozen in an independent detached checkout at
`5b7d79f8f07d6b21428124fdd3aafb106057842b`, whose parent is the PR #41
merge commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. An independent
clone of the Git bundle recovered the same source. The recipe 10 receipt
and original product inventories still verified.

The installed Flutter launcher sources `bin/internal/bootstrap.sh` when
present. The preflight fixture proved that an ignored file or a dangling
link at that path fails before launcher invocation. The real SDK had no
local bootstrap. A separate configuration-only invocation generated two
Swift package manifests and two Swift source files under the Runner's
ephemeral packages directory. The generated-configuration snapshot hashes
the manifests, sources, and other package files. An injected Swift source
change after CLI compilation blocked the App build before Xcode ran.

The loader fixture accepted a canonical dyld-cache-only system load and
rejected parent-directory components, dot components, and repeated path
separators in system load paths. A clean-build fixture changed a tracked
file's executable bit during compilation without changing its digest.
The final committed-tree comparison failed the build and its receipt.

Python 3.15.2 byte-compilation, `git diff --check`, and all 226 local tool
tests passed, including tests that observe owned processes.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The executor reported macOS 27.2.1 arm64, Flutter 3.50.0, bundled Dart 3.14.0,
Xcode 27.2 (27B52), Apple Clang 21.0.0, and macOS SDK 27.2. The App reported
`0.1.0-rc.1+7` with Apple short version `0.1.0` and build `7`. The CLI
reported `0.1.0-rc.1`. Neither build used engineering mode.

Both runs independently matched the before-after compilation map of 137
inputs with digest
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`. The
generated configuration also matched, including both Swift manifests and
the two Swift source files. The toolchain, dependency graph, source, flags
and full bundle composition agreed. The App runner differed in 64 signature
bytes and 14 symbol-string-table bytes. The CLI executable differed in 96
signature bytes and six symbol-string-table bytes. All file-backed Mach-O
sections, including the embedded CLI Dart AOT image, matched. The
comparison run `run-025` independently passed with materials NOT_RUN.

The reference CLI passed eight synthetic SQLite operations. The original
reference App passed VM write, read and relocated read with normal shutdown.
The candidate-bound replacement probes observed the serial replacement
library in isolated App and CLI copies through a synthetic empty-port response.
The checks used no hardware.

## Recipe 10 handoff record

Recipe 10 selected **`build/phase-1e4/frozen-source/build/phase-1e4/run-022/`**.
It was built without `--allow-dirty` from frozen commit
`8f66583a77516f4cd6d5d58747e7c0895d3186e5`.
The development branch and this detached checkout have independent Git state.
The reference passed build, product, candidate-specific runtime, materials
collection, and strict materials verification. The comparison build
`run-023` passed its independent check with materials status NOT_RUN.

| Exact run-022 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `77aa71d2355a4446fb6b3919ce85326852e11878c327a187436ce739e110b2cf` |
| `evidence/candidate-inventories.json` | `c9caacc6dc92475d6c64bb9001302237687c765c066e231b2437e4dd32036057` |
| `evidence/build-receipt.json` | `a6c856747e774059683d07a979e33384c43929b9d49e53b57479718b9796666a` |
| `evidence/product-checks.json` | `d339aa3098b1a3d93c1ac63144a119f7d8dc45e4b03b601671938fda365d05d1` |
| `materials/materials-manifest.json` | `2f303a0db44726aa576e3b05e4f86d79b6aaedc9547064c06d27bfa6748e4dbb` |

The pre-staging check passed from the retained frozen checkout with this command.

```sh
cd build/phase-1e4/frozen-source
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-022 --require-frozen
```

The local source commit and its Git history can be recovered from
`build/phase-1e4/review-frozen/phase-1e4-source.bundle`, SHA-256
`7026ccecc41d956cd1bf0f5865f063e075280b6cca8a31a9c87cf342ed997b11`.
Artifact verification uses the retained checkout and evidence.

Strict materials verification covered 276 entries with no open gates.
The material manifest and its embedded receipt both name the frozen commit.
The corresponding-source archive contains the release entry, test, supporting
tools, root `.gitignore`, and build guide. The receipt-bound product report
and dependency graph accompany them. See
`build/phase-1e4/frozen-source/build/phase-1e4/review-evidence/source-archive-check.log` and
`build/phase-1e4/frozen-source/build/phase-1e4/review-evidence/run-022-final-check.log`.

Use the recorded complete App and CLI bytes for staging. Rebind the product
identities and materials after the applicable signing and packaging steps.

## Recipe 10 review verification

Both builds use a detached clean checkout of the local freeze commit
`8f66583a77516f4cd6d5d58747e7c0895d3186e5`, whose parent is the PR #41
merge commit `583dc5f7ee9d5d173237e8eb60b06dd388304b80`. The development checkout
retains its branch, HEAD and staged state. The build indexes and receipts
record an empty working-tree status and `engineeringDirtyMode: false`.
The Git bundle restores the frozen source commit independently of the
development checkout. Bundle restoration was verified with a fresh clone.

The SDK verifier compared the installed checkout with its pinned Git tree.
The file bytes, executable modes and raw Git symlink targets matched. The
installed Windows files with checkout-only CRLF differences matched the
pinned attributes and blob contents. A regression fixture proved that an
edited `macos_assemble.sh` marked assume-unchanged is rejected before the
Flutter launcher even when Git reports a clean SDK. The product inventory
preserved raw symlink spelling and rejected the invalid slash-terminated
regular-file target. The handoff gate rejected engineering evidence even
when checked at its recorded commit.

Local Python 3.15.2 tool discovery passed all 222 tests, including the
owned-process supervision tests. Python byte-compilation and
`git diff --check` also passed.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The executor reported macOS 27.2.1 arm64, Flutter 3.50.0, bundled Dart 3.14.0,
Xcode 27.2 (27B52), Apple Clang 21.0.0, and macOS SDK 27.2. Both runs
reported App `0.1.0-rc.1+7` (Apple version `0.1.0`, build `7`) and
CLI `0.1.0-rc.1`.

The same 137 compilation inputs matched before and after both compilers,
with SHA-256 `6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
The lockfile, graph, external sources, toolchain, source, and normalized build
recipe matched. Both inventories recorded 74 App entries and six CLI entries.
Differences were restricted to 64 signature and 14 symbol-string-table bytes
in the App runner, and 96 signature and six symbol-string-table bytes in the
CLI executable. All file-backed Mach-O sections, including those in the
embedded CLI Dart AOT image, matched. The independent check of `run-023`
passed with materials status NOT_RUN. See `review-evidence/comparison.json`
under the frozen checkout's `build/phase-1e4/`.

The reference `run-022` CLI passed eight offline SQLite operations. The
original App passed VM write, read, and relocated read with normal shutdown.
The complete isolated App and CLI copies loaded the replacement serial
library with a synthetic empty-port response, bound to the original bytes.
No hardware was used.

## Recipe 9 engineering record

Recipe 9 recorded **`build/phase-1e4/run-020/`** as engineering evidence. The build, product and
candidate-specific runtime checks, materials collection, and strict materials
check passed. The comparison build `run-021/` passed its independent check.
Its materials status is NOT_RUN.

| Exact run-020 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `e76caf62ccc8eac48feceae262ed0797b97b66a2b1335f7d61e0e6b1f4a9f5dd` |
| `evidence/candidate-inventories.json` | `8674f49c78ae2ae458523fa84f50d908fb546b9faa7bce9435b3fdb1d6d856c6` |
| `evidence/build-receipt.json` | `2804e32b9536c584e099e1f029ec74c3fcbdd4d2c127557a8ab08be7ed314510` |
| `evidence/product-checks.json` | `8891b325164988768d88a52e9e677b59740cf072791bbd17078c2b280c0170a9` |
| `materials/materials-manifest.json` | `1f135eaf89231c4e48bffff6530f9ba91440d46f32c805ec688513e8bd44c73d` |

The original checkout verified the engineering run with this command.

```sh
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-020
```

The strict materials check covered 276 entries with no open gates.
The corresponding-source archive contains the release entry, test, supporting
tools, root `.gitignore`, and build guide. The material package also delivers
the receipt-bound product report and dependency graph. See
`build/phase-1e4/review-product-evidence/source-archive-check.log` and
`build/phase-1e4/review-product-evidence/run-020-final-check.log`.

Use the exact recorded App and CLI for staging. Rebind the product identity
and materials to the signed and packaged bytes at the applicable release steps.

## Recipe 9 review verification

The builds started from PR #41's merge commit
`583dc5f7ee9d5d173237e8eb60b06dd388304b80` with the reviewed working tree
recorded via `--allow-dirty`. The host was macOS 27.2.1 arm64 with Python
3.15.2, Flutter 3.50.0, bundled Dart 3.14.0, Xcode 27.2 (27B52), Apple Clang
21.0.0, and macOS SDK 27.2. The products identify as App `0.1.0-rc.1+7`,
CLI `0.1.0-rc.1`, Apple short version `0.1.0`, and build `7`.

The tests reproduced a changed tracked file hidden by `assume-unchanged`.
The clean build refused it before package resolution and accepted the committed
fixture. Inventory checks rejected an unreadable directory and direct and chained
links that left and re-entered the bundle. A child that wrote JSON to stdout
and a Flutter-style diagnostic to stderr passed parsing and retained both
stream digests. The product report and index rejected substituted signing
details, a missing report reference, and a report that disagreed with the
receipt. The recipe 8 build receipt still verified against its original products.

The reference candidate's validator verified the two locked FFI asset IDs for
each of `macos_arm64` and `macos_x64` against the corresponding bundled
slices. The complete `run-020` CLI passed eight offline SQLite operations.
The VM verified App write, read, and relocated read with normal shutdown.
The isolated native library replacement probes matched both original products
and observed the replacement using a synthetic empty-port response.

Local tool discovery passed 219 tests, including tests that observe owned
processes. Python byte-compilation and `git diff --check` passed.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

Evidence is under `build/phase-1e4/review-product-evidence/`.

Both builds independently matched the 137-input before/after snapshots
(`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`).
The lockfile, dependency graph, source, recipe, toolchain, and product
composition agreed. Inventories contained 74 App and six CLI entries.
All file-backed Mach-O sections matched, including the embedded Dart AOT
image. Only the App runner (64 signature bytes and 14 symbol-string-table
bytes) and CLI executable (96 signature bytes and six symbol-string-table
bytes) differed. The independent check passed for `run-021`, with materials
status NOT_RUN. See `comparison.json` and `run-021-check.log` in the
review evidence directory.

## Recipe 8 handoff record

Recipe 8 selected **`build/phase-1e4/run-018/`**. The build, product and
candidate-specific runtime checks, materials collection and strict materials
check passed. The comparison build `run-019/` passed its independent check.
Its materials status is NOT_RUN.

| Exact run-018 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `f4aec9b6639a762a7552f63dcc064bb0bc5bf9b97b0abbfae5d388cb850a7390` |
| `evidence/candidate-inventories.json` | `6c3b81fbf3a3442f361faf4fde7b9eff19d3e825955afe88837f77ee09e8e5d4` |
| `evidence/build-receipt.json` | `b5f1a0140741dc0fbd158baf463bf8dfcf8030e23f37c95539592c270271108a` |
| `materials/materials-manifest.json` | `73662044a39a62d0bab62a035dcc93b28640f43a3c426f95db4aef0b25134b84` |

The recipe 8 handoff was verified with this command.

```sh
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-018
```

The strict materials check verified 275 entries with no open gates. The
corresponding-source archive contains `.gitignore`, the release builder,
its test and helpers, and `docs/releases/phase-1e4-build.md`. The materials
also include the receipt-bound copy of `resolved-graph.json`. See
`build/phase-1e4/review-provenance/source-archive-check.log` and
`build/phase-1e4/review-provenance/run-018-final-check.log`.

Use the recorded complete products for staging. Rebind product identities and
materials to the signed and packaged bytes at the applicable release steps.

## Recipe 8 review verification

Both builds started from PR #41's merge commit
`583dc5f7ee9d5d173237e8eb60b06dd388304b80`. The builder and review changes
were present as working-tree input and recorded with `--allow-dirty`.
The host was macOS 27.2.1 arm64, with Python 3.15.2
(`/opt/homebrew/bin/python3`), Flutter 3.50.0, bundled Dart 3.14.0,
Xcode 27.2 (27B52), Apple Clang 21.0.0, and macOS SDK 27.2. The candidates use App
`0.1.0-rc.1+7`, CLI `0.1.0-rc.1`, Apple short version `0.1.0`, and build `7`.

Both builds derived the same 137 first-party compilation inputs before and
after each compiler. Their input snapshot digest was
`6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
The lockfile and resolved dependency graph digests were respectively
`e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c` and
`75fb32718000e9d7342a5d1120051d04c3f1cd3d1deeb3e51be4b852b6db4185`.

The review checks rejected an absolute link to a file inside the original
bundle and edits to the build index's dirty state, lockfile digest, or graph
digest. The verified dependency graph accompanies the build receipt in the
materials. The standalone materials receipt verifier still accepts the
original recipe 7 receipt and its recorded products.

A local HTTP fixture stalled after sending 8 bytes of a 34-byte archive,
then returned the complete archive on retry. Curl with redirected stdout
left 42 bytes. Curl given the private output path published only the 34
pinned bytes. A real Git filesystem-monitor fixture exercised both SIGTERM
and a one-second deadline. The deadline case published both failure records,
observed child exit, and released the checkout lock in 1.39 seconds.
Superseded attempts `run-016` and `run-017` were canceled and retain
their failure evidence.

The following passed locally with 212 tests. Python byte-compilation and
`git diff --check` also passed. See `build/phase-1e4/review-provenance/`
for command, build, comparison, and strict-check logs.

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
```

The exact `run-018` CLI passed eight synthetic SQLite operations. In the
macOS VM, the original App passed write, read, and relocated read, each with
normal shutdown. Native replacement used isolated copies of the complete CLI
and App and a synthetic empty-port response. Both replacement observations
were bound to the original candidate bytes. The checks used no hardware.

The two inventories have the same composition and modes, including 74 App
entries and six CLI entries. The App runner differed in 63 signature bytes
and 14 symbol-string-table bytes. The CLI executable differed in 94 signature
bytes and five symbol-string-table bytes. All file-backed Mach-O sections,
including those in the embedded Dart AOT image, matched. Other product files
matched byte for byte. The comparison verified the normalized argv and working
directories, provider and SDK identities, generated configuration, and
externally resolved sources. See
`build/phase-1e4/review-provenance/comparison.json`.

The comparison run `run-019` independently passed `check`. Its materials
status is NOT_RUN.

## Recipe 7 handoff record

Recipe 7 selected **`build/phase-1e4/run-014/`**. It passed the build, product
and candidate-specific runtime checks, collection and strict materials
verification. The comparison build `run-015/` passed its independent check.
Its materials were NOT_RUN.

| Exact run-014 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `79e1235f1e29f8d0e0fa93235be432a0d58199074c8aa7f2dda87c9b66582fe8` |
| `evidence/candidate-inventories.json` | `03fc3348977b90966a23ee8eaf854ed9ebfdc55e17b1a107f8a7e4df4faaf98e` |
| `evidence/build-receipt.json` | `c97998d5e184709a7f6014705b1f34bd0403b26b1f2773e7761874c3371c275e` |
| `materials/materials-manifest.json` | `faf4293c47fdac0092bd1954f700688f231561ea7402d054525a515a8933d509` |

The recipe 7 handoff was verified with this command.

```sh
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-014
```

The final check exited 0 with overall, build and materials status PASS.
Its strict recheck returned no failures. See
`build/phase-1e4/review-inventory/run-014-final-check.log`.

Use the recorded complete products for staging and rebind them after signing
and packaging. Earlier runs retain their historical evidence.

## Recipe 6 handoff record

Recipe 6 selected **`build/phase-1e4/run-012/`**. The build, product,
candidate-specific runtime and strict material checks passed. The comparison
build `run-013/` passed its build and independent product check. Its material
stage is NOT_RUN.

| Exact run-012 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `655537dacbbc3d378790abf56c053ff9a47094c445386acd2d9031ac293b117c` |
| `evidence/candidate-inventories.json` | `0d14030ea50f640238548c68d862f4ba2ebf5b56b21799ed5a65fe4972b46d42` |
| `evidence/build-receipt.json` | `53440251e5e29d7dbd1fc8eb2462055267f8b70369b5b4a285a57166cb780fb5` |
| `materials/materials-manifest.json` | `1e7ae1457a8cec0a42668f8b35703679a16f7b1132f05cdfa8a8a147222bb3d1` |

The recipe 6 handoff was verified with this command.

```sh
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-012
```

The final check exited 0 with overall, build and materials status PASS.
Strict material verification returned no failures. See
`build/phase-1e4/review-validator/run-012-final-check.log`.

Use the recorded complete products for staging and rebind them after signing
and packaging. Earlier runs retain their historical evidence.

## Recipe 5 handoff record

Recipe 5 selected **`build/phase-1e4/run-010/`**. This run passed the build,
product and candidate-specific runtime checks, materials collection and strict
material verification. The independent comparison build, `run-011/`, passed
its build and product check. Its material stage is NOT_RUN.

| Exact run-010 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `271757164b94a67821a90ce28a89cbd27a0c14e73906a7a96a4919e1e7a63fc7` |
| `evidence/candidate-inventories.json` | `d800523a3ba7b49fd80fe48644aef6d173664d003bbed819bc0dc4aaac0b7af8` |
| `evidence/build-receipt.json` | `e9ba6a3341586d48d52968224959147d8b2b6b6bb6f3756ef3c7a76d6102c42f` |
| `materials/materials-manifest.json` | `60cdcb313ba5d9b662a19052dbaee143416bf6f21a4fd45cb647fae5478c60d9` |

The recipe 5 handoff was verified with this command.

```sh
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-010
```

This final check exited 0 with overall, build and materials status PASS.
Its independent strict rerun returned no failures. See
`build/phase-1e4/review-finalization/run-010-final-check.log`.

Use the recorded complete products for staging and rebind them after signing
and packaging. The earlier runs below retain their original evidence.

## Recipe 4 handoff record

Recipe 4 selected **`build/phase-1e4/run-008/`**. This run passed the build,
product, candidate-specific runtime and strict materials checks. The comparison
build `run-009/` passed its build and independent product check. Its material
stage is NOT_RUN.

| Exact run-008 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `0e9caa53ce2120ce9c4b5a1d8f4ae53c5e1c494856fcd8f00b523ac611c48f44` |
| `evidence/candidate-inventories.json` | `12960c808c45d54c7efb172ad6036c9944ff348b2fe3e3bde024796651875a1b` |
| `evidence/build-receipt.json` | `fb3011a1580b12ae2873afbba39901784b8ca1bf564324df217fb01b7d9664bb` |
| `materials/materials-manifest.json` | `8fb09b8477c0e58f20845596518d8aac48d19b76603316a7716f88e0834c4768` |

The recipe 4 handoff was verified with this command.

```sh
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-008
```

The command exited 0 with overall, build and materials status PASS. The
independent strict rerun returned no failures. See
`build/phase-1e4/review-integrity/run-008-final-check.log`.

Use the recorded complete product bytes for staging and rebind them after
signing and packaging. The previous runs below retain their original evidence.

## Recipe 3 handoff record

Recipe 3 selected **`build/phase-1e4/run-006/`**. The complete products passed
the build, static and candidate-specific runtime checks, materials collection,
and independent strict material verification. The comparison build,
`run-007/`, passed its build and independent product check. Its material stage
is NOT_RUN.

| Exact run-006 handoff file or directory | SHA-256 for evidence files |
| --- | --- |
| `app-derived/Build/Products/Release/Meshchan.app` | See the full inventory |
| `cli/bundle/` | See the full inventory |
| `build-info.json` | `06ae761cfce3bae93c7105813a7571fca7c2aaa59d578abc49a76bd60ad89f41` |
| `evidence/candidate-inventories.json` | `95f87e93340e560f288cd7696044f66e02157bbe975e404e9ac162721b2f9793` |
| `evidence/build-receipt.json` | `27feb5bf7c46e11f1fd25a80748c12b0222c62bb786b1903a53daac5de3acd92` |
| `materials/materials-manifest.json` | `85abc67805a821721e9eda344faffbed7d5d0d5699f1b75c10431c5ec1cf26f3` |

The recipe 3 handoff was verified with this command.

```sh
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-006
```

The command exited 0 with overall, build and materials status PASS. Its
strict rerun also returned an empty failure list. The final log is
`build/phase-1e4/review-requalification/run-006-final-check.log`.

Staging, signing and packaging must consume the recorded complete products and
rebind changed bytes. The earlier run-004 record is historical. Its helper and
source identities correspond to the original recipe, so the current checker
rejects it against this checkout. The observed rejection is retained in
`build/phase-1e4/review-requalification/run-004-current-check.log`.

## Original acceptance of run-004 and run-005

The original acceptance selected `build/phase-1e4/run-004/`, with complete
App and CLI, successful compilation and product checks, candidate-specific
no-hardware observations and a
strict material PASS. `run-005/` is the independent comparison rebuild: its build
and product checks pass; its candidate-specific material stage is **NOT_RUN**.
These are local results, not remote CI or public-release acceptance.

The original reference recorded these exact bytes:

- App: `build/phase-1e4/run-004/app-derived/Build/Products/Release/Meshchan.app`.
- Complete CLI: `build/phase-1e4/run-004/cli/bundle/`.
- Index: `build/phase-1e4/run-004/build-info.json`, SHA-256
  `ac891e1451c94bdaf77ac5cc1565c89b9fb44bd35ef281f3cd0a42ebef17718b`.
- Full inventory: `build/phase-1e4/run-004/evidence/candidate-inventories.json`.
- Materials: `build/phase-1e4/run-004/materials/`; manifest SHA-256
  `3d995a648718e9e311d0277cec5f2256b9cad9fa471084a6f0deed0af80b1cf7`.
- Comparison, exact hashes and preservation receipt:
  `build/phase-1e4/validation/comparison.json`, `candidate-summary.json`, and
  `preservation-check.json` in that same validation directory.

Do not rebuild silently after acceptance. Staging, formal signing and packaging
must preserve this provenance and rebind all changed bytes. Materials/current
build hashes here are separate from future signed/stapled/DMG download hashes.

## Baseline, source and environment

Work began on clean `master` at
`583dc5f7ee9d5d173237e8eb60b06dd388304b80`, the merge of PR #41. The actual
GitHub query returned MERGED, mergedAt `2026-11-17T17:40:21Z`, final PR head
`ebfc7fa455b9c19ecfe8634d0f0a6eeded260a93`. The prompt's `dd1c4ce` is included;
the final head also fixes build-7 diagnostic assertions. No merge/reset/clean,
commit, tag, force push or publication was performed for this task.

Both comparison builds explicitly used `--allow-dirty`: their uncommitted entry,
tests and documentation are recorded by actual source hashes, Git status and
helper identities. HEAD alone is not asserted to represent these bytes. Their
source identity is `05d81bc503d6c9c4f1c8c2c51020d38b1720398d7b962dadc31092cba3311208`.
This is a stable engineering input snapshot, not a final frozen release commit.

Product identity remains App `0.1.0-rc.1+7`, CLI `0.1.0-rc.1`, Apple short
`0.1.0`, build string `7`, Bundle ID `org.meshchan.meshchan`. No product source,
resource, license/CLA policy, dependency, data directory, schema or wire input
changed. The independently derived compilation map remains the same actual 137
inputs as trusted build 7, SHA-256 `6fa1acafe3687925b92413c45061ff8e8f1335ccb69653b794f24827e3928331`.
The number 137 is observed, never a hardcoded gate. New build tools and build
documentation do not enter App/CLI compilation. No automatic build allocation
occurred.

| Observed tool/environment | Actual identity |
| --- | --- |
| Python invocation | `/opt/homebrew/bin/python3`, stable 3.15.2; actual `sys.executable` `/opt/homebrew/opt/python@3.15/bin/python3.15` |
| Flutter | 3.50.0 stable, `/opt/homebrew/share/flutter`, framework `ab2912035e160d9cad6306df307576da6128ebdb` |
| Engine | revision `371f77202a73e8dff57a8b3bff75bca55c090aee`, content `bf601093ad255aaf5c6d0fc5c4f9acfa60943b2a` |
| Bundled Dart | 3.14.0, revision `fa8c1270c374c1346931583a17c3b7f278d3822d` |
| Xcode / Apple Clang | 27.2 (27B52) / 21.0.0 (clang-2100.4.1.1) |
| macOS SDK | 27.2, actual SDK and compiler paths recorded in build-info |
| Host / target | macOS 27.2.1 (26B131), arm64 / macOS arm64 |
| Root lock | `e25ed2f37c339206d8587e42e00a0b901bb37874554813840e2025b03bbf847c` |

The installed SDK matches the reviewed framework/engine/Dart/source-tree pins.
Prebuild evidence also hashes the actual Release engine, both Flutter snapshot
tools, Dart runtime/compiler snapshots, Python and Clang, and 91 resolved hosted
package trees. Generated Flutter configuration and package resolution have
separate identities. All are rechecked after compilation; the first-party map
is not described as all compiler/toolchain inputs. Local child PATH and selected
configuration are in build-info; no environment/credential dump is retained.

## Actual builds, comparison and integrity

Commands used the same final repository entry, with separate new owned runs:

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-004 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py build --flutter /opt/homebrew/share/flutter --output build/phase-1e4/run-005 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-005
/opt/homebrew/bin/python3 build/phase-1e4/validation/compare.py
```

Both actually ran locked resolution, Release `--config-only`, bundled
`dart build cli` and isolated Release Xcode builds. Exact argv/cwd, start/end,
exit code, process-tree exit and log hashes are in each receipt. App compiler
steps took 157.595 and
171.496 seconds, both exit 0.
No clean, old-product copy, signing override or cache purge substituted for a
compiler command. Before maps precede both compilers; after-CLI and after-App
maps were independently recalculated and all three match in both runs.

Comparison PASS includes source/helper identity, all 137 first-party inputs,
91 external package trees, lock, graph, toolchain, generated configuration,
version and recipe (only run-directory names normalized). Inventories contain
41 App file/link entries and 3 CLI files in each run; paths, modes and link
targets agree. CLI contains `bin/meshctl`, serial and SQLite dylibs. Normal
Framework internal symlinks are preserved. Per-slice native hook correspondence,
actual loader resolution, plist/CLI versions and deep/strict signatures pass.
App runner, AOT and frameworks contain arm64 and x86_64; CLI is arm64. This is
not Intel runtime acceptance.

| Actual product file | run-004 SHA-256 | run-005 SHA-256 |
| --- | --- | --- |
| App Info.plist | `9c1790ce515afc1cff01a88406c3cfeb21d363af6375fa3888dc392550ecd4a4` | `9c1790ce515afc1cff01a88406c3cfeb21d363af6375fa3888dc392550ecd4a4` |
| App runner | `35ce706cd4d480ff1947577cbe894dac3dc8854e8ee56926687d34c46cbf49e7` | `ae7490979c1e72bed280295b1ab57d338f17a2c0a5f60d3beb19332a4ae686c9` |
| App.framework AOT | `4fca58f6463d946e5d984d44ca2348fd4f665d84dff33e4a8f63cde24b1fbfb5` | `4fca58f6463d946e5d984d44ca2348fd4f665d84dff33e4a8f63cde24b1fbfb5` |
| CLI bin/meshctl | `092bf249568d718ec249f8755645e0ab259531afb8e71bcb1ea6a4eefe220695` | `a0e36ab847c91f2ce31c7a579ac787d671717f356ed33c52a40dd61f910eff55` |

| Evidence | run-004 SHA-256 | run-005 SHA-256 |
| --- | --- | --- |
| build-receipt.json | `bef2b936b006b1b6084c7a06cf5dc243bf3eccb37bf043389a69848b782242ab` | `92a9e94c048ce26fee356d03bb551102b79aae68378ef36d0e4fe6cefe242956` |
| candidate-inventories.json | `4aa52ffbcba100eafb5ac5b635485d796851e784fc3311a48a21335784712cf8` | `718b22fcfba3995e5aa705801e0adceb650c5fbfe131a39ed56f88d6d6a2caf1` |
| candidate-checksums.txt | `fd94a9b272795868173f01765f53fe5422119b26754d339e2ae26cd7ebebd604` | `6fe37fd2b6c0ab923ab79edb2cd64b8dee2f3e0adddd95200f7280645e49d5dc` |

The only changed App file is its runner: 14 differing symbol-string-table bytes
identify `run-004` versus `run-005` object paths (seven per slice), and 64 bytes
are in the two slice signature blobs. The only changed CLI file is `bin/meshctl`:
5 symbol-string-table bytes identify the compiler's random temporary
`snapshot.aot` directory, and 96 bytes are in its outer/embedded signature blobs.
All other bytes agree after classifying those exact load-command-derived ranges;
there are **zero unclassified differing bytes**. UUIDs are unchanged. All actual
file-backed sections match, including the second embedded CLI AOT Mach-O at
offset 4,734,976 and its text, constants and DWARF sections. The comparison script
records actual section hashes and rejects unclassified differences; this is not
a generic assumption that every difference is signing. App.framework and all
other product files are byte-identical.

Actual local signatures are ad hoc with no team. The App's observed effective
entitlements include `com.apple.security.get-task-allow=true`; CLI entitlements
are empty. Existing Release source entitlements/team/runtime configuration was
not changed. These actual local conditions must be reconsidered and revalidated
under 1E.6 formal signing.

The entire original trusted build-7 App, CLI and material inventories were
captured before work and remain unchanged (`preservation-check.json`: PASS).
The reference bytes also remain unchanged after replacement tests on copies.

## Candidate-specific observations and strict materials

The [VM skill](../../.agents/skills/macos-vm-gui-testing/SKILL.md) and existing
signed executor were used through SSH, with strict host key, VirtualMac UUID,
console, owned fixture, PID/argv and focus guards. No host GUI automation or
hardware enumeration was used. The fresh executor run was
`20261117T175116Z-product-8100`; its session lives under
`build/phase-1e4/run-001/validation/vm/` because it was prepared during an earlier
trial. Its actual sourceApp is the new run-004 replacement copy, not a run-001
product. The probe independently verifies that association.

Reference evidence is in `run-004/validation/`:

- `cli-smoke.json` / `.log`: eight actual native CLI processes passed synthetic
  SQLite draft create/reopen, profile/settings persistence and history/export.
- `serial-rebuild.json` / `.log`: unchanged locked serial sources rebuilt, then
  genuine early empty-list/marker source modification rebuilt and substituted
  only into complete isolated copies (`/tmp/meshchan-lgpl-20mchh5n/`). The CLI
  product actually called it. The function returns before the OS backend.
- `vm-launch`, `vm-nav-device`, `vm-refresh`, `vm-quit`, `vm-settled` logs: the
  replacement App PID 15430 called the modified library through Device/Refresh,
  then normal Command+Q released owner/worker/resources; PID absence confirmed.
- `attach-vm-final.log`: final App/CLI candidate payload and guest replacement
  hash independently verified; no old observation was rebound by editing JSON.
- `vm-runtime-reports.json`: original complete reference App write/read and
  complete-copy relocation/read all passed, report compiled build 7, closed
  normally and independently confirmed all three PIDs absent. No default data
  directory or real port was accessed. `vm-finish.log` records normal executor
  completion. Actual validation scripts are retained with the ignored evidence.

```sh
/opt/homebrew/bin/python3 tool/release_sdk_sources.py check --workspace build/phase-1e3-source --flutter /opt/homebrew/share/flutter
/opt/homebrew/bin/python3 tool/rebuild_release_serial.py --archive build/phase-1e3/downloads/libserialport_plus-1.0.5.tar.gz --archive-sha256 9246f3a0909e4bc87ef2ac1366bbc2eb350d139f976a277dd5c29b8d3dc085e3 --cli build/phase-1e4/run-004/cli/bundle --app build/phase-1e4/run-004/app-derived/Build/Products/Release/Meshchan.app --output build/phase-1e4/run-004/validation/serial-rebuild.json
# After guest observations and normal finish, the actual final attachment:
/opt/homebrew/bin/python3 tool/rebuild_release_serial.py --archive build/phase-1e3/downloads/libserialport_plus-1.0.5.tar.gz --archive-sha256 9246f3a0909e4bc87ef2ac1366bbc2eb350d139f976a277dd5c29b8d3dc085e3 --cli build/phase-1e4/run-004/cli/bundle --app build/phase-1e4/run-004/app-derived/Build/Products/Release/Meshchan.app --output build/phase-1e4/run-004/validation/serial-rebuild.json --attach-vm-evidence build/phase-1e4/run-001/validation/vm --vm-config /Users/xiaoyu/.config/meshchan-vm/config.json
/opt/homebrew/bin/python3 tool/build_release.py materials --output build/phase-1e4/run-004 --downloads build/phase-1e3/downloads --probe build/phase-1e4/run-004/validation/serial-rebuild.json --sdk-source-workspace build/phase-1e3-source
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-004
```

The exact fully expanded material commands are in separate material ledgers
under `run-004/evidence/materials-*/`; they explicitly pass the actual repository,
SDK, full App/CLI, new output, verified downloads, fresh probe, before map,
candidate checksums, real build receipt and SDK source workspace. No 1E.2 default
record is used. Collection exited 0 with PASS, 273 materials and empty openGates.
The independent strict check exited 0 with PASS, integrityAndCoverage and
thirdPartyMaterials PASS, failures empty. Both freshly checked original SDK
archives and regenerated all three GN source closures, rather than trusting a
cached PASS. The separate SDK-source check also passed.

GPL corresponding source is PASS. Its actual first-party archive has 340 files,
including the exact new builder, tests, helpers and
`docs/releases/phase-1e4-build.md`; the integration extracted the delivered
builder/guide and compared their hashes. Source archive SHA-256:
`5ea9c0d59616251721e419c61c242a9d5a4e7ecc596e909e082f7416d9ddf78e`. Existing pub, Flutter framework, engine/Dart,
native and LLVM source/build coverage is retained. Only the two explicit 1E.3 /
1E.4 result reports are excluded to avoid report/hash recursion; instructions,
arbitrary docs and tracked inputs remain covered.

The final independent `check` repeats actual input/product/evidence checks and
strict material verification after writing this fixed result report. Its log is
`build/phase-1e4/validation/run-004-final-check.log`. The observed final exit was
0: overall PASS, buildStatus PASS and materialsStatus PASS. This report is outside source hashing by the tested fixed
exclusion, not an arbitrary user-configurable omission.

## Tests, failures and scope

```sh
/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'
/opt/homebrew/bin/python3 -m py_compile tool/build_release.py tool/build_release_test.py
git diff --check
```

Final Python discovery: **184 tests PASS**, including 16 new release-entry tests
and affected material/SDK/identity/process regressions. Actual final output is
`build/phase-1e4/validation/python-tests-release-final.log`. New tests cover phase
ordering, source drift/immutable before maps, compile/missing-product failures,
SDK/platform/Python/version rejection, shared-lock/output/space/symlink safety,
real owned-child timeout and signal cleanup without touching another process,
product/log/receipt/inventory tampering, external native source drift, exact
material arguments, REVIEW_REQUIRED rejection, mixed progress/JSON logs and
fixed-report exclusion. Existing tests preserve historical format-1 receipts,
dev.3 defaults, four-member inputs/resources/license changes and old-probe binding.

Initial restricted invocations could not write Flutter cache or observe `ps`;
the authorized native runs then executed those checks successfully. No global
PATH/toolchain/security setting changed. Preliminary run-001/run-002 completed
under earlier implementation snapshots and are retained as trials, not handoff
candidates. Run-003 was deliberately interrupted after an entry correction;
its FAIL receipt records SIGTERM and confirmed owned-process exit. It is never
counted as one of the accepted pair. All retries used new directories; no failed
or historical evidence was overwritten. Earlier sandbox/test failures remain in
the session and trial logs and are not relabeled as successful runs.

Not run: the full Dart/App business/GUI/IME matrix, real USB/RF, DMG, Developer
ID, notarization, installation/upgrade, clean-environment/minimum OS/Intel
acceptance, remote CI or publication. There is no unresolved VM/probe blocker for
the reference candidate. GPL-3.0-only, attribution, CLA and contribution policy
remain unchanged. 1E.5 and later stages retain their separate release gates.

## Review follow-up

The original recipe failed in a fresh checkout because the Dart input parser
needed `package:yaml` before locked resolution had produced the package
configuration. The failure was reproduced in an isolated clone. The revised
recipe snapshots repository source before locked resolution, rejects source or
lockfile drift immediately after resolution, then compares compilation inputs
across Release configuration. The complete before-build map still precedes
both compiler commands.

A separate real-process reproduction showed that a parent exiting 9 left the
runner waiting on a live helper until the five-second test deadline. The revised
runner starts owned-process cleanup when it observes the nonzero exit and
preserves exit 9 in the step ledger. A successful parent still drains its
helpers naturally before the runner hashes the log.

`/opt/homebrew/bin/python3 -m unittest discover -s tool -p '*_test.py'`
passed **187 tests** with Homebrew Python 3.15.2 and OS process observation
available. New coverage checks immediate cleanup on failure, natural drain on
success, and rejection of source changes during resolution and configuration.
The build-order fixture starts without a package configuration. Reproduction
and test logs are in `build/phase-1e4/review-follow-up/`.

The revised entry was also run in a new temporary clone at
`/private/tmp/meshchan-1e4-fixed.VM2Kd8` with no `.dart_tool` directory.
From that checkout, the actual commands were:

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/review-fixed --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/review-fixed
```

Locked resolution, the complete CLI and Release App builds, and the independent
product and evidence check passed. The 137-entry before, after-CLI and after-App
maps were byte-identical and matched run-004's map. The build and check logs
are `bootstrap-fixed.log` and `bootstrap-fixed-check.log` in the follow-up
evidence directory. The new run's material stage is NOT_RUN.

The earlier run-004 and run-005 receipts, logs, product checksums and inventories
still verify against their original files. The run-004 build-info and material
manifest hashes match the original reference above. They record the earlier
recipe and source snapshot.

## Second review corrections

Recipe 3 validates the SDK's pinned HEAD and tracked files before the launcher
runs. The build and independent checker supervise the Flutter version probe with
the checkout lock, command deadline, owned-process cleanup and evidence ledger.
A real SIGTERM regression held the checkout lock during the probe, observed
process exit, verified FAIL in both build records, and reacquired the lock.
Separate tests reject stale cached identity and a reported pin mismatch.

Material collection rejects existing and dangling symlinks at its destination.
The corresponding-source archive includes the root `.gitignore`, and the build
guide describes initializing a local Git snapshot from an extracted archive.
The loader check reads actual Mach-O dependency load commands and verifies that
the selected bundled file contains the loading architecture. Dylib install IDs
are excluded. Tests cover a wrong slice, a plain file and a valid symlink to a
matching universal library.

Full Python discovery passed **192 tests** using Homebrew Python 3.15.2 with
`/bin/ps` available. The earlier reviewer sandbox denied process observation.
The actual full suite log is
`build/phase-1e4/review-requalification/python-tests.log`.

The two new builds used the final recipe 3 and the same actual source cut
`9f08a6e901667e569164ed40598add280e003df953a293fa5c4901b8f2aea9c8`.
They retained App `0.1.0-rc.1+7` and CLI `0.1.0-rc.1`. Both compiled directly
from this checkout into new output trees.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-006 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-007 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-007
```

Both before/after build input maps contain the same 137 entries and match the
original compilation-input identity. The comparison recorded matching source
and helper identities, toolchain, external package trees, generated settings,
resolution, normalized recipe, and inventory composition. All file-backed
Mach-O sections match, including the embedded CLI AOT image. The App runner
differs in 14 path-string bytes and 64 signature bytes. The CLI executable
differs in six path-string bytes and 96 outer/embedded signature bytes.
All other product files match, and no byte differences were left unclassified.
The comparison is in `build/phase-1e4/review-requalification/comparison.json`.

Run-006 passed eight real offline CLI SQLite checks. Guest executor
`20261117T193103Z-product-17714` verified that the isolated replacement App
called its modified empty-list library and shut down normally. The new CLI
replacement also called its modified library. A separate guest copy of the
original complete App passed write, read and complete-copy relocation/read with
normal shutdown. The actual evidence is under `run-006/validation/` and the VM
session is under `review-requalification/vm/`, both below `build/phase-1e4/`.

The delivered first-party archive was unpacked into a fresh temporary directory.
The documented local Git initialization and commit succeeded. Git tracked
`.gitignore` and `pubspec.lock`, ignored both the run output and generated package
configuration, and reported a clean tree. The extracted builder accepted a new
output path. Evidence is in
`build/phase-1e4/review-requalification/archive-git-check.log`.

The actual candidate-bound materials command ran with the following inputs.

```sh
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-006 \
  --downloads build/phase-1e3/downloads \
  --probe build/phase-1e4/run-006/validation/serial-rebuild.json \
  --sdk-source-workspace build/phase-1e3-source
```

Collect passed with 273 materials and no open gates. The independent strict
check passed integrity and coverage and third-party materials with no failures.
The GPL first-party archive contains 341 files and has SHA-256
`c0d8bcecfcfb9f28b2b7f5aefb2ac60f351d7f27c2a5ce076a918d0bc942e7b5`.
The build-info material references bind both logs and the exact manifest.

## Third review corrections

Recipe 4 verifies each CLI sibling library with `codesign` before accepting the
bundle. On disposable copies of run-006, recipe 3 accepted both the serial
and SQLite libraries after their signatures were individually removed. Recipe 4
rejected each copy at that library's signature check. The source products were
preserved. Evidence is in
`build/phase-1e4/review-integrity/unsigned-cli-reproduction.log`.

The checker binds the selected run name, canonical App and CLI paths,
build evidence, command logs, checksums, and accepted material references to the
requested directory. A copied index is rejected even if it is relabeled and
its product paths are rewritten. The receipt's commit must match the selected
index and checkout. The materials stage checks the manifest and embedded
receipt against that commit, and a same-tree Git commit change fails before
collection.

All Dart input snapshots use the supervised command runner. The real SIGTERM
regression confirms the checkout lock is held during the snapshot, the owned
process exits before lock release, and both build records preserve FAIL.

Material destinations and writable caches cannot overlap either product.
The index writer uses a unique temporary file, and its reserved names cannot be
used as materials destinations. Once materials are accepted, subsequent
collection requests fail before replacing any accepted references.

The direct materials collector also rejected a download cache under the
preserved CLI bundle before creating either the cache or the materials output.
Full Python discovery passed **199 tests** with Homebrew Python 3.15.2 and OS
process observation available. The final suite and separate Flutter/Dart
SIGTERM logs are under `build/phase-1e4/review-integrity/`.

The revised reference candidate passed eight offline SQLite CLI checks. Guest
executor `20261117T195609Z-product-21076` observed the safe modified App library
and normal owner and worker release. The modified CLI library was also called.
The original complete App passed guest write, read and copied-bundle read.
The new probe and logs are under
`build/phase-1e4/run-008/validation/`.

The new pair was built and compared from the same recorded source snapshot,
`cb7c9e8f4f3106f5536941520d632e1ba433e59325237ec6d3fa0b22dab35a42`.
Each build used the same locked inputs and retained App `0.1.0-rc.1+7` and
CLI `0.1.0-rc.1`.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-008 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-009 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-009
```

The independent comparison passed. The 137 compilation inputs, versions,
toolchain, dependency graph, external sources, normalized recipe and product
composition matched. All file-backed Mach-O sections matched, including the
embedded CLI AOT image. The App runner differed in 14 path-string bytes and
64 signature bytes. The CLI executable differed in six path-string bytes and
96 signature bytes. Other files matched and no byte differences were left
unclassified. The second run's material stage is NOT_RUN. See
`build/phase-1e4/review-integrity/comparison.json`.

The candidate-bound materials command was:

```sh
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-008 \
  --downloads build/phase-1e3/downloads \
  --probe build/phase-1e4/run-008/validation/serial-rebuild.json \
  --sdk-source-workspace build/phase-1e3-source
```

Collection and strict verification passed for all 273 materials. The manifest,
embedded receipt and checkout all identified commit
`583dc5f7ee9d5d173237e8eb60b06dd388304b80`. The first-party archive digest is
`3b2324c7be88e0dd30996ef9de14ce740262d01f937bfc7cb5acc48dda40c903`.
A second collection request using a fresh name was rejected before creating that
directory. Both the accepted index and manifest passed their original SHA-256
checks after the request. See
`build/phase-1e4/review-integrity/accepted-retry.log`.

## Fourth review corrections

Recipe 5 checks overlap using the device and inode of existing directories
and ancestors. On this Mac, `meshchan.app` and `Meshchan.app` resolved to the
same directory identity. A direct collect request for a new cache below that
alias failed before either the cache or output directory was created.

The checker requires `prebuild-identities.json` in the index and compares the
verified file digest with the original build receipt. Regression fixtures
rejected a missing reference, a changed file, and a changed file whose index
digest had also been updated.

The build defers SIGTERM and SIGINT through command cleanup, product
validation, inventory generation and final status publication. Real SIGTERM
tests reached inventory generation and publication of the final index. Both
tests observed the shared checkout lock remaining held until FAIL and the
signal were recorded in both files. An interrupted PASS publication was
replaced with FAIL before lock release.

Failed signing checks retain captured stderr in the failure receipts and
terminal output. On a disposable CLI copy with an unsigned serial dylib, the
actual diagnostic included `code object is not signed at all` and
`In architecture: arm64`.

Full Python discovery passed **203 tests** using Homebrew Python 3.15.2 with
process observation available. Test, case-alias and codesign logs are in
`build/phase-1e4/review-finalization/`.

Run-010 passed eight offline CLI SQLite checks. Guest executor
`20261117T202222Z-product-24705` verified the modified empty-list App library
and normal owner and worker release. The modified CLI library was also called.
The original complete App passed guest write, read and copied-bundle read.
The new probe and logs are under `build/phase-1e4/run-010/validation/`.

The two recipe 5 builds use the same source snapshot,
`c5e3b6522e4f5ca2647478e698fe982bf913b1927affd0eb05724a9f692df458`,
and retain App `0.1.0-rc.1+7` and CLI `0.1.0-rc.1`.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-010 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-011 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-011
```

Both builds and the independent comparison passed. Before and after files
recorded the same 137 compilation inputs. The two runs' prebuild identity
files matched each other and their respective receipts, at SHA-256
`cf826b243c553062786f59dd2b28edb92978dbf8522ad85da6286ccddc8e10bc`.
The source, toolchain, external packages, normalized recipe and complete
artifact composition also matched. All file-backed Mach-O sections, including
the embedded CLI AOT image, matched. The App runner differed in 14 path-string
and 64 signature bytes. The CLI executable differed in six path-string and 96
signature bytes. There were no unclassified differences. Run-011 independently
passed `check` and its materials were NOT_RUN. See
`build/phase-1e4/review-finalization/comparison.json`.

The exact run-010 materials invocation was:

```sh
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-010 \
  --downloads build/phase-1e3/downloads \
  --probe build/phase-1e4/run-010/validation/serial-rebuild.json \
  --sdk-source-workspace build/phase-1e3-source
```

Collection passed with 273 materials and no open gates. The independent strict
check passed integrity and coverage and third-party materials, with an empty
failure list. The manifest and its embedded receipt identified
`583dc5f7ee9d5d173237e8eb60b06dd388304b80`. The first-party archive has SHA-256
`1164985abfbb18a2286a4fda4341b6e9209a1905f799dc24a88cfed5f83be418`.

## Fifth review corrections

Recipe 6 checks SDK probe write locations before both collection and recheck,
including the evidence directory and individual reports, the GN executable,
the generated SDK configuration and GN scratch roots. The SDK probe repeats
the check just before its first write. A real collector invocation with
`workspace/evidence` pointing into the preserved CLI bundle was rejected before
the out-of-run directory or the candidate received new files. Regression
fixtures also reject an individual report symlink and a GN scratch-root
symlink in both flow directions.

Product inventories now cover the product root and all real subdirectory modes.
The product checksum file still covers regular files. In a disposable copy of
run-010, changing only `lib/` from mode `0755` to `0700` changed the inventory
while every file hash stayed identical.

The checker compares the index's generated configuration, toolchain and helper
identities with the verified, receipt-bound prebuild record. Its live
comparisons use that prebuild record. A fixture with an edited index is rejected
before current configuration can be used.

The complete product validation runs as a supervised child, including the CLI,
Mach-O and signature tools and native asset mapping. The parent owns its
deadline, command log, checkout lock and cancellation cleanup. The regression
ran a real CLI fixture that hung after startup and verified that the deadline
stopped and drained the validator and executable. Signature diagnostics are
retained in the product validator log.

Full Python discovery passed **207 tests** with Homebrew Python 3.15.2 and OS
process observation available. Evidence is in
`build/phase-1e4/review-validator/`.

Run-012 passed eight offline CLI SQLite checks. Guest executor
`20261117T205507Z-product-27675` verified the safe modified empty-list App
library and normal owner and worker release. The modified CLI library was
also called. The original complete App passed guest write, read and
copied-bundle read. See `build/phase-1e4/run-012/validation/`.

The two recipe 6 builds use the same source snapshot,
`f4e102393ddcaeaa3ac8f1a70c313873e2362cfeff22501b47d0a54b931f6519`,
with App `0.1.0-rc.1+7` and CLI `0.1.0-rc.1`.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-012 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-013 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-013
```

Both builds, the comparison and the independent check of run-013 passed.
The comparison covers the 137 actual compilation inputs, source and helper
identities, tools, dependency graph, external package sources, normalized
recipe and complete inventory composition. Each App inventory has 74 entries
including 33 directories, and each CLI inventory has six entries including
three directories. These counts include the product roots. Directory modes
match. All file-backed Mach-O sections matched, including embedded CLI AOT.
The App runner differed in 14 path-string and 64 signature bytes, and the CLI
executable in six path-string and 96 signature bytes. No differences were left
unclassified. Run-013's materials are NOT_RUN. See
`build/phase-1e4/review-validator/comparison.json`.

The exact candidate-bound materials invocation was:

```sh
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-012 \
  --downloads build/phase-1e3/downloads \
  --probe build/phase-1e4/run-012/validation/serial-rebuild.json \
  --sdk-source-workspace build/phase-1e3-source
```

Collection and strict verification passed for all 273 materials, with no open
gates and no failures. The manifest and embedded receipt both identified
`583dc5f7ee9d5d173237e8eb60b06dd388304b80`. The first-party archive SHA-256 is
`362cf822e4987877402b6127f5edede80c96baa3b79f4543ee5013de96749f78`.

## Sixth review corrections

Recipe 7 rejects unsupported product entries and binds the complete inventory
SHA-256 to the receipt. A disposable CLI copy reproduced the former FIFO
omission. The current inventory rejected that same FIFO without opening it.
The directory-mode regression also rejects an edited inventory whose index hash
was refreshed after the mode change. The materials verifier checks and delivers
the receipt-bound inventory when that field exists. Older format-1 receipts
remain readable by the historical materials path.

The runner logs and supervises the toolchain commands, including Dart, Xcode,
Clang discovery and version, macOS SDK paths and versions, host identity and
Git checks for the pinned Flutter SDK. A real process fixture substituted a
sleeping child for the Xcode probe and verified timeout and owned-process exit.

Both material downloaders use exclusively created files in the cache and pass
the file descriptor to curl. Publication follows pinned hash validation.
Regressions preserve the existing symbolic and hard links at the old partial
name and the candidate bytes they reference. A hash mismatch leaves no accepted
archive or temporary download behind.

Full Python tool discovery passed **210 tests** with Homebrew Python 3.15.2 and
OS process observation enabled. The first run exposed a fixture expectation
that omitted an existing test directory. The final run compares the complete
fixture inventory before and after the action. Test and reproduction evidence
is in `build/phase-1e4/review-inventory/`.

Run-014 passed eight offline CLI SQLite checks. Guest executor
`20261118T044034Z-product-34721` verified the safe modified empty-list App
library and normal owner and worker release. The modified CLI library was
also called. The original complete App passed guest write, read and
copied-bundle read. See `build/phase-1e4/run-014/validation/`.

Recipe 7 used source snapshot
`6001c9805ba47c58b14ddf36f5744cd1ba907b63dfc8aaaa3aa65f4589bdfba9`
with App `0.1.0-rc.1+7` and CLI `0.1.0-rc.1`.

```sh
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-014 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py build --output build/phase-1e4/run-015 --allow-dirty
/opt/homebrew/bin/python3 tool/build_release.py check --output build/phase-1e4/run-015
```

Both builds and the independent comparison passed. The 137 compilation inputs,
tools, package identities, normalized recipe and inventory composition match.
The App inventory contains 74 entries and the CLI six, including directories.
All file-backed Mach-O sections match, including embedded CLI AOT. The App
runner differs in 14 path-string bytes and 64 signature bytes. The CLI
executable differs in six path-string bytes and 96 signature bytes. There
were no unclassified differences. Run-015 passed independent `check` and
its material stage is NOT_RUN. The actual comparison is in
`build/phase-1e4/review-inventory/comparison.json`.

The exact reference materials invocation was:

```sh
/opt/homebrew/bin/python3 tool/build_release.py materials \
  --output build/phase-1e4/run-014 \
  --downloads build/phase-1e3/downloads \
  --probe build/phase-1e4/run-014/validation/serial-rebuild.json \
  --sdk-source-workspace build/phase-1e3-source
```

The independent strict verification passed all 274 materials with no open gates
or failures. The receipt and manifest both record the inventory SHA-256 at the
top of this report. The delivered inventory was compared byte for byte with the
build-time file. The first-party archive SHA-256 is
`6a25e7f3ac5a12556189cf179e71a6887595f910c257f931df5b11ae96ba6823`.
