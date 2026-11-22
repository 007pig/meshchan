# Meshchan RC1 Build 10 validation summary

This summary applies to Meshchan App `0.1.0-rc.1+10` and the complete
`meshctl 0.1.0-rc.1` bundle for macOS arm64. Both products are built from
`be88abba92c47e3814e5bca4b8cc1e8c1efd6ad7`. The engineering distribution
uses local ad hoc code signatures. The matching staged `release-manifest.json`
lists the image size, SHA-256, and acceptance recorded before the follow-up
privacy findings.

The exact-source CI run passed on attempt 1. The complete local Release
build independently checked the App and CLI identity and all eight delivered
Mach-O files for local build paths. Strict materials verification bound the
corresponding source, dependency archives and rebuild inputs to the same
build. The build-time synthetic libserialport replacement exercised the CLI
loader and a separate VM App probe. [Exact Build 10 CI](https://github.com/007pig/meshchan/actions/runs/45014763866)

The held 669,238,209-byte image has SHA-256
`4fbb88c824d696e688e8d049db94ba1f408ff03dc7872607a9f115c049bc937a`.
Its independent checks covered 693 image inventory entries, 403 entries in
the first-party source archive, and eight Mach-O files. The actual shipped
replacement tool built and locally signed synthetic App and CLI copies from
the maintainer's independent extraction. Both copies loaded the expected
replacement and exited normally. A separate review found that the held tool
rejects signed inputs carrying download quarantine. The original
path audit missed a local temporary `snapshot.aot` path in the CLI Mach-O
and a macOS temporary-directory prefix in `docs/development.md` inside the
first-party source archive. Both findings were reproduced in both retained
Build 10 images. The privacy gate remains open for publication.

The signed App also opened an owned data snapshot closed by the retained
Beta CLI, saved one draft, and quit normally. The exact Build 10 CLI
independently confirmed the preserved drafts, profiles, settings and
History, including the new draft. Full replacement of the historical Beta
App remains pending recovery of that App and its close evidence.

On an isolated macOS 27.2.1 (26B131) arm64 guest, Safari preserved the revised
download's quarantine and source metadata. Finder installed the App from a
verified read-only mount to `~/Applications`. The complete CLI and materials
were copied to a separate support directory and matched the image inventory.
The co-located layout in the engineering guide awaits separate verification.
In the tested split layout, the guest used individual approvals for
`meshctl`, `libsqlite3.dylib`, and Meshchan. The installed App saved a
draft and a setting offline. The CLI returned exit 69 while the App held
the data directory. Normal Quit, the independent CLI read, and a second
App launch confirmed both changes. SIP and Gatekeeper stayed enabled.

On the arm64 host, the installed App listed the selected USB port and
completed one Check on a Heltec V4.3 OLED with protocol code 14. The
session and host observer released their resources, and the App quit
normally. The finite RF round trip and active Cancel remain open.

Earlier observations apply to their respective images. The full quarantined
Safari install and Beta build 5 replacement were exercised with Build 8.
Build 9 hardware acceptance used source
`01cfacb7fc166a0078962a99d9e673750aabad65`. The Build 10 asset manifest
records the earlier acceptance against the independently verified Build 10 image.

Use the [engineering guide](rc1-build10-engineering-guide.md) for the
download, approval and normal Quit sequence. The
[source materials guide](rc1-build10-source-materials.md) maps the shipped
corresponding sources and the user library replacement procedure.
