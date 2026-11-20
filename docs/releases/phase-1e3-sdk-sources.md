# Native SDK corresponding source

This is the source/build-input supplement to the single
[App/CLI materials contract](phase-1e3-licenses.md). It preserves the community
`GPL-3.0-only` decision and the separate CLA. Third-party source keeps its original
licenses. Large archives and owned checkouts stay under ignored `build/`.

## Exact scope and identity

The installed Flutter framework is `ab2912035e160d9cad6306df307576da6128ebdb`;
its engine artifact identifies `371f77202a73e8dff57a8b3bff75bca55c090aee`, content
hash `bf601093ad255aaf5c6d0fc5c4f9acfa60943b2a`. These are distinct commits.
Both commits' `engine/src` Git tree is
`63775f6f125fd281ef19073f3ac5e854774f1fbf`. The checker independently reads both
objects from the installed SDK repository and compares them to the reviewed pin.
The engine source archive is generated from the engine commit, including its
DEPS, CI configuration and engine build documentation. Independently downloaded
engine-stamped official framework and Dart SDK archives are SHA-256 pinned. Their
actual framework/runtime/version/revision members must match the installed SDK
byte for byte; the product section comparisons then bind these inputs to App/CLI.
This supplies a binary-to-source identity chain in addition to SDK version text.

The bundled Dart SDK is 3.14.0, revision
`fa8c1270c374c1346931583a17c3b7f278d3822d`. Its original runtime, sdk, build,
tools, pkg, third_party and utils subtrees and required root files are supplied.
The authentic Git commit object is retained for original version-generation
scripts, with its SHA-1 equal to the revision. Reconstruction installs only that
commit and shallow metadata in the owned Dart checkout. It neither creates a
synthetic commit nor lets version scripts accidentally use Meshchan's parent Git
repository. Engine version arguments are supplied from independently bound
engine/content/Skia/Dart identities because source archives lack checkout Git
metadata; original upstream source files are not patched.

Three native build roots are checked separately:

| Product content | Original GN target and configuration |
| --- | --- |
| App engine arm64 slice | `//flutter/shell/platform/darwin/macos:flutter_framework_dylib`, macOS arm64 release |
| App engine x64 slice | Same target, macOS x64 release; source coverage confers no Intel product support |
| CLI embedded runtime | Dart `//runtime/bin:dartaotruntime`, macOS arm64 release, matching the SDK runtime used by `dart compile exe` |

The original engine macOS CI recipe (`ci/builders/mac_host_engine.json`) is in
the engine archive. Its framework packaging target wraps this native framework
target. Source verification disables unrelated tests/examples, remote execution
and LTO, and uses the existing bundled SDK as the bootstrap compiler. This is a
source dependency check, not a claim that these are all original factory build
flags, or that compilation, signing or bit-identical reproduction was performed.
The supplied release target definitions retain the original compile/link and
generation rules. Use the upstream recipe when reproducing the factory build.

Engine and standalone Dart native dependency versions are resolved independently
from their original DEPS. In particular, their ICU and zlib pins differ. Source
archives cover the selected Skia, ICU, BoringSSL, image/text libraries, Dart VM,
libcxx/libcxxabi, GPU/shader build inputs and their build definitions. Some
archives are needed by host generator programs or GN configuration; this does
not label all their code as present in the product. Complete subtree archives
preserve headers, nested notices, checked-in generated files and regeneration
inputs. Optional submodules are represented by authentic Gitlink IDs for tree
verification; missing optional content is permitted only when no selected source
or evaluated build input refers to it. Explicit DEPS child pins override parent
Gitlinks where upstream specifies that layout.

The standalone Dart link rule uses the compiler package's static `libc++.a`.
Its LLVM revision is `3493720eca95cf844a8d7e58fdd12e0e5644e7d0`, distinct from
the engine compiler revision `07d67299a15ce03b053736e2d31a668ee0576987`.
For each, original libcxx, libcxxabi, libunwind and compiler-rt sources plus
cmake, runtimes, llvm/cmake, llvm/include and llvm/utils inputs are supplied.
The exact Dart compiler package has CIPD instance
`I3jJODfJ3oWA8URw1WreYho4oBujaac9omMjvCJR2dsC`, archive SHA-256
`2378c93837c9de8580f14470d56ade621a38a01ba369a73da26323bc2251d9db`.
Its original `source_manifest.json`, license, package manifest and
`include/c++/v1/__config_site` are retained. The provenance identifies the same
LLVM revision; the header preserves ABI namespace/version and feature settings.
The whole compiler archive stays in ignored downloads. Its other compiler-only
dependencies do not become Meshchan runtime components merely through tool use.

Xcode/macOS frameworks and dylibs listed under `/System/Library` and `/usr/lib`
are provided by the operating system and are not copied into the products.
Unmodified general-purpose compiler executables and bootstrap SDKs are build
tools. Bundled native/runtime library source is supplied separately; it is not
discarded under a broad SDK/System Library exemption.

## Acquire, reconstruct and verify

The reviewed URLs, SHA-256s, Git tree/blob/commit identities, DEPS relationships,
generated gclient/compiler metadata, scope and exceptions are in
`tool/release_sdk_sources.json`. That file is subordinate input to the existing
materials manifest, not a second product inventory. DEPS expressions are read
with a restricted AST evaluator; arbitrary DEPS Python is never executed.

From the repository root, use the existing SDK and Python:

```sh
/opt/homebrew/bin/python3 tool/release_sdk_sources.py prepare --workspace build/phase-1e3-source-new --flutter /opt/homebrew/share/flutter
/opt/homebrew/bin/python3 tool/release_sdk_sources.py check --workspace build/phase-1e3-source-new --flutter /opt/homebrew/share/flutter
```

`prepare` requires a new owned checkout. It never overwrites an existing source
checkout, SDK or pub cache. It acquires exact source archives, verifies SHA-256
and reconstructed Git trees, then extracts originals with executable modes and
internal source symlinks. Required root files are also checked as Git objects.
It obtains the pinned small GN tool and generates native release build graphs.
Subprocess Python always uses the selected interpreter. Expect several GB of
temporary source space and several minutes for the first acquisition/check.

To reconstruct sources from a collected delivery without fetching those source
archives again:

```sh
/opt/homebrew/bin/python3 tool/release_sdk_sources.py prepare --workspace build/phase-1e3-restored --flutter /opt/homebrew/share/flutter --materials build/phase-1e3-final/materials
```

The tool verifies the delivered source rules, restores original archives and
compiler configuration members, and still acquires unmodified build tools if
needed. It does not require the large compiler executable archive when the
verified configuration members are already delivered. The helper also fetches exact official binary reference artifacts for SDK
correspondence checks when absent. They are verification/build-tool inputs, not
missing corresponding source. The matching installed Flutter/Dart SDK, Xcode,
a compatible Ninja and compiler remain prerequisites
for compilation. Source recipients can also run the delivered `rebuild/` copy
of this helper beside its JSON specification.

Strict checking recomputes Git trees including omitted Gitlinks, checks DEPS
revision/source matches, verifies all original build scripts before running
them, and freshly generates all three GN graphs. It traverses dependencies from
each required native root, checks actual code/input/script bytes against the
original archives, requires generated inputs to have a producer in that closure,
and verifies every GN regeneration/build-definition input. Output includes the
full normalized graphs and a report of source/build-input hashes. It fails
missing or changed inputs, absent roots, empty coverage, wrong source revisions,
missing runtime source sets and incompatible SDK identities. A stored PASS flag
or removed manifest row cannot satisfy these independent checks.

Two narrowly reviewed upstream metadata defects are preserved without patching:
the Dart source list names eight old `runtime/vm/protos/perfetto` header paths
although its actual includes use checked-in `third_party/perfetto/protos`
headers; engine's inja secondary BUILD file lists deleted `string_view.hpp`
although pinned inja uses standard `<string_view>`. Each exception binds the
original declaration, real replacement/header use and revision. The checker
scans source includes to reject an actual reference to the obsolete header.
Exceptions apply only to these unused header declarations, never missing
compiled source, build scripts, source generators or their required inputs.

## Compile from the prepared inputs

Preparation preserves the original source and emits graph evidence using a new
scratch output for every check. To configure persistent native build outputs
with real local Xcode paths and the exact unmodified compiler tools:

```sh
/opt/homebrew/bin/python3 tool/release_sdk_sources.py configure-build --workspace build/phase-1e3-source-new --flutter /opt/homebrew/share/flutter --target app-arm64 --target app-x64 --target cli-arm64
```

This first repeats source verification, obtains the pinned compiler packages and
extracts them only under the owned source tree. It discovers local Xcode SDK,
platform and toolchain paths with xcrun/xcode-select, regenerates release Ninja
definitions, and records the exact compiler archive hashes and Ninja argv in
`evidence/build-configuration.json`. It does not compile or modify a product.
The original GN arguments are also in `sdk-source-report.json`.
Before writing, the command checks the report, compiler extraction paths, and
persistent GN output paths. Existing files at write destinations must be owned
regular files. Compiler symlinks must match their pinned archive entries, and
Dart's generated SDK links may point to the corresponding SDKs in the selected
Xcode developer directory.

The executable native compilation commands are then:

```sh
ninja -C build/phase-1e3-source-new/checkout/engine/src/out/rebuild-app-arm64 flutter/shell/platform/darwin/macos:flutter_framework_dylib
ninja -C build/phase-1e3-source-new/checkout/engine/src/out/rebuild-app-x64 flutter/shell/platform/darwin/macos:flutter_framework_dylib
ninja -C build/phase-1e3-source-new/checkout/engine/src/flutter/third_party/dart/out/rebuild-cli-arm64 dartaotruntime
```

The supplied original toolchain-runtime `runtimes/CMakeLists.txt` builds libc++,
libc++abi and libunwind with the accompanying CMake/include/utils inputs; its
compiler-rt subtree includes its own build definitions. For CLI ABI-compatible
reconstruction preserve `__config_site` (ABI version 2, namespace `__2`) and
the recorded Apple arm64 target. Runtime sources are provided at the compiler
package's source revision, not substituted with the engine's other libcxx pin.
General compiler/Ninja/CMake tools may be installed independently without
requiring those tools' entire source distributions in the product materials.

These native commands are build instructions, not recorded native compilation
results. This step validates the actual input closure and successful GN
generation. The separate libserialport original/modified rebuild and product
replacement results remain the existing independent evidence. Replacing an
engine/runtime in a complete product changes bytes and may require rebuilding
the AOT application snapshot with matching tools; subsequent artifact binding,
signing and installation conditions must be checked for that resulting product.

## Collection and release integration

Pass `--sdk-source-workspace build/phase-1e3-source` to both `collect` and `check`
of `tool/release_materials.py`. They independently run this native source check.
All required archives, original compiler configuration, source rules, rebuild
instructions and graph evidence are copied into the same materials delivery.
No verifier result is treated as a replacement for actually delivering files.

1E.4 must capture its actual SDK/native/resource/product inputs; 1E.5 must deliver
the complete materials and matching GPL source in the product, an adjacent
directory or an accompanying source attachment on the same release entry. If
source is a separate download, publish it with equivalent access and clear
binary-to-source version/hash mapping when publishing the binary; no future
URL is claimed here. GPLv3 section 6 access conditions and LGPL library source
remain applicable. Final archive/DMG checksums are separate from these source
material hashes. 1E.6 repeats formal-signing replacement and installation
information checks; the current local experiment is not that acceptance.

Any lock, graph, SDK/engine/Dart/compiler revision, native input, font/resource,
product or signing change requires recollection and strict rebinding. Reviewed
source pins cannot silently accommodate a different SDK. No public release,
engine/runtime rebuild, signing-policy change or new product build is made here.

Fixed upstream references include the [engine macOS recipe](https://github.com/flutter/flutter/blob/371f77202a73e8dff57a8b3bff75bca55c090aee/engine/src/flutter/ci/builders/mac_host_engine.json),
[Dart DEPS](https://github.com/dart-lang/sdk/blob/fa8c1270c374c1346931583a17c3b7f278d3822d/DEPS),
and the original [GPLv3 source and conveyance terms](https://www.gnu.org/licenses/gpl-3.0.html).
The actual collected fixed source bytes supply the evidence.
