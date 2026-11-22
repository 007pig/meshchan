# Phase 1E.11 release materials validation

Validation took place on November 22, 2026 from a clean starting checkout at
`183f906fa82831c4af2a708c9ad47251b497328e`, after PR #49 merged. The original
image was compiled from `01cfacb7fc166a0078962a99d9e673750aabad65`. The
post-review software cut was `1152097eebd91b13b45d29dbd60cef794d7a5c3d`.
These are independent from this working-tree documentation revision.
The [maintainer handoff](../releases/phase-1e11-release-materials.md) lists the
status and next actions. [PR #49](https://github.com/007pig/meshchan/pull/49)

## Original candidate and inputs

| Check | Result |
| --- | --- |
| Independent selection | The historical selection digest and all seven image, checksum, signing, and DMG records matched. The image still has 676,240,035 bytes and SHA-256 `49e25d6580486276850177fc51f68093462c26212daa0b12770ed7b6e26d66f2`. Original pins matched before and after the mount. |
| Image and payload | Original checksum, `hdiutil verify`, read-only mount, full 763-entry payload comparison, and detach passed. The initial default sandbox attachment failed with `Device not configured`. The successful retry used the authorized read-only disk-image operation. |
| Products | App bundle plist values, arm64 CLI and its native libraries, code signatures, and full App nested seal passed. The App contains additional x86_64 slices. The tested distribution architecture is arm64. |
| Source closure and inventory | Rehashed 457 source entries from the frozen Git commit. The 398 archived source members matched their recorded bytes and executable class. All 139 declared compilation inputs occur in that archive with matching bytes. All 331 registered material files matched the original strict material manifest. |
| Receipts and original tools | The candidate admission verifier checked 1,172 referenced evidence roots. It passed after mapping original source files to an independent Git export and original packaging tool files to the matching preserved snapshot. The direct recheck first encountered the later worktree's CI workflow. A plain Git export of the upstream tools then differed in the recorded POSIX mode of the VM helper. The preserved original tool snapshot supplied the bound bytes and modes. |
| Replacement and offline runtime | The original signing receipt binds App and CLI synthetic replacement, relocated runtime, and final integrity. The independent DMG receipt binds offline CLI and VM App runtime from that extraction. This review rechecked those receipts and their bindings. |
| Historical hardware | Reviewed the original case selection, 275 indexed evidence files, five operation start/result pairs and 24 GUI references. The [public acceptance summary](phase-1e10-hardware-acceptance.md) preserves the automated validator `UNKNOWN`, offline replay `REVIEW_REQUIRED`, and the eventual manual `PASS`. The original USB/RF run occurred on November 22 before this review. |

The independent original Build 9 signing and DMG receipt digests are
`c151db57914ead57342c221e9879137c1858fee632142c58212589967699c680` and
`fb44b9aebcc08ee71cb3d44bb39d71791afeee3251aed7382e17e0a4821b0a0d`.
The first-party archive digest is
`975e01bcf77cbebdc4183a80da79b93a1ffa82da51ae455698bdb370c633e230`.
The [source and license index](../releases/rc1-engineering-source-materials.md)
maps the actual installed and in-image paths and the two separate SDK runtimes.

## GitHub and durable retention

The read-only repository checks found PR #49 merged, with base
`9941ec57dbd3e921e0bf6ebc5dc38bd20e44733b` and the two recorded commits.
No tag or release was visible. No exact original source run was visible.
The later push run `45007478263` passed on attempt 1. Both retained job ZIPs
matched the API object sizes and SHA-256. The existing CI verifier checked the
pinned later snapshot with `--require-artifacts`. The initial invocation omitted
that flag and rejected the snapshot identity. The successful invocation used
the original workflow and snapshot digests and retained evidence.
[Later CI run](https://github.com/007pig/meshchan/actions/runs/45007478263)

The original evidence is currently accessible. The documented engineering
archive contains a durable Build 8 seal and restore. Build 9's rechecked
candidate inputs still include temporary extraction, signing and replacement
evidence. The private handoff pins those locations and preserves copies of
selected receipts and the modified native image probe. The original probe
was a working-tree change relative to the base tool commit. Build 9 still
needs the retention tool's CI and committed-tool identity inputs and a separate
successful durable recovery attempt.

## User material and boundary checks

The actual complete candidate CLI passed version and help checks from outside
its installation directory. Covered entry points include directory option
placement and command and group help. An isolated path fixture tested the copy
with spaces, complete CLI layout, framework symlinks and the existing
destination guard. CLI checks ran without USB I/O. Build 8's downloaded
first-install and Beta upgrade and Build 9's later software cut retain their
own scope. This review did not repeat install, upgrade, replacement, VM GUI or
RF acceptance. It did not rebuild, re-sign or repackage the candidate.

The staged external files are the four release documents, a derived
288-file corresponding-materials index, the original DMG checksum, the
proposed release manifest, and the outer attachment checksum. The original
DMG is mapped separately and held private. The manifest records leaf names,
sizes and hashes. The outer checksum adds the manifest and excludes itself.
No standalone original build, signing, package or hardware receipt is staged
for public use.

Both checksum files passed `shasum -a 256 -c` in an isolated flat layout
using the exact mapped image bytes. The staging verifier reproduced all
nine proposed asset identities. Ten focused negative tests rejected wrong
source and material references, missing and modified files, replaced original
checksums, unknown assets, symlink substitution, duplicate entries, and
checksum self-reference.

Inspection of the image identified path-bearing original provenance and
synthetic serial replacement logs. Inspection also found original worktree
path strings in the main App executable and CLI. The external-file review
and checksum verification do not resolve the embedded image disclosure.
The immutable image therefore remains held, with `materialsStatus:
INCOMPLETE`, `publicationReadiness: BLOCKED`, and
`publicationState: NOT_PUBLISHED`. The private map records no approved upload
files.

## Local verification commands

Python checks used `/opt/homebrew/bin/python3`, Python 3.15.2. The installed
candidate tests used macOS built-in shell, disk image and signature tools.
The documentation check passed 190 repository-local links and 10 immutable
GitHub source references. The flat attachment layout passed six local links
and the same 10 source references. Bash and Zsh parsed all nine shell blocks.

```sh
/opt/homebrew/bin/python3 -B tool/check_product_version.py \
  --expected-version 0.1.0-rc.1 --app-build 9
git diff --check
```

The ignored 1E.11 handoff retains the asset checks, public review copies,
candidate admission replay, and private evidence index. The product and
publication gates are tracked in the [handoff](../releases/phase-1e11-release-materials.md).
