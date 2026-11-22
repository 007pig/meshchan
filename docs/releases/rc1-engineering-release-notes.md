# Meshchan 0.1.0-rc.1 Build 9 engineering release

Meshchan RC1 Build 9 pairs the Apple silicon App `0.1.0-rc.1+9` with the complete
`meshctl 0.1.0-rc.1` bundle. This engineering candidate comes from frozen source
`01cfacb7fc166a0078962a99d9e673750aabad65`. The App and CLI use local ad hoc code
signatures. The read-only disk image is unsigned and unnotarized. macOS may
require individual approvals under its normal security policy. [Frozen product source](https://github.com/007pig/meshchan/commit/01cfacb7fc166a0078962a99d9e673750aabad65)

| Asset identity | Value |
| --- | --- |
| Disk image | `Meshchan-0.1.0-rc.1-build9-macos-arm64-local.dmg` |
| Size in bytes | `676240035` |
| SHA-256 | `49e25d6580486276850177fc51f68093462c26212daa0b12770ed7b6e26d66f2` |

Use the [engineering guide](rc1-engineering-guide.md) to verify the DMG,
install the complete products and accompanying materials, handle item-specific
macOS approval, back up or upgrade, and run the installed CLI. The original
`SHA256SUMS` covers the DMG, and `RELEASE-SHA256SUMS` covers the final
attachments and `release-manifest.json`. The [source and materials index](rc1-engineering-source-materials.md)
lists the corresponding source, GPL-3.0-only project license, third-party terms,
and rebuild and native-library replacement materials carried in the DMG.

## Changes and scope

- The App and CLI share a device-specific USB startup compatibility path for
  the recognized Heltec V4.3 OLED Companion. Build 9 adds bounded startup-prefix
  recovery and a completion query for that device. Initialization failures
  remain possible. [Build 9 Device Check source notes](https://github.com/007pig/meshchan/blob/01cfacb7fc166a0078962a99d9e673750aabad65/apps/meshchan_app/README.md#explicit-finite-device-checks-1d6)
- The App provides offline Drafts, Profiles, Settings, History and one-page
  summary export, plus finite Device Check and recorded PING/Responder. Device
  access is explicit and USB-only. A completed Check yields a historical
  snapshot. RF exchange, long-run reliability, range, and throughput require
  their own evidence. The engineering scope is macOS arm64 and excludes Intel
  Macs, mobile platforms, BLE, background receiving, content sync or
  distribution, and automatic reconnect or resend.
- The later PR #49 commit `1152097eebd91b13b45d29dbd60cef794d7a5c3d` hardens
  handshake timing, frame and prefix recovery, and trace and cleanup paths.
  Those changes are outside this image. Its software and offline results and
  successful CI run apply to that later source. [Follow-up source](https://github.com/007pig/meshchan/commit/1152097eebd91b13b45d29dbd60cef794d7a5c3d), [Follow-up CI run](https://github.com/007pig/meshchan/actions/runs/45007478263)

## Verified scope and remaining gates

- The frozen Build 9 disk image passed independent signing and DMG acceptance,
  including the packaged App guest and CLI host offline runs. The signed
  candidate also passed synthetic modified-library loading for the App and
  CLI. Those replacement checks exercised loading with an empty synthetic
  port list.
- On November 22, 2026, the locally installed image passed finite hardware
  acceptance on one macOS 27.2.1 (26B131) arm64 Mac and one selected Heltec
  V4.3 OLED Companion, firmware `v1.18.0-81dbae5`, protocol code `14`. The
  review covered closed App Device Check, one exact RF PING/PONG with the
  source-only OpenHop acceptance peer, active Responder Cancel, normal Quit and
  release, installed CLI `info`, independent History, and final integrity.
  See the attached public acceptance summary
  `phase-1e10-hardware-acceptance.md` for the case limits and retained earlier
  observations.
- The previous downloaded first-install and Beta build 5 upgrade passes on
  macOS 27.2.1 (26B131) arm64 apply to RC build 8. The full quarantined
  first-install flow, the Beta upgrade, and the separate serial-library
  assessment behavior remain open for this Build 9 image. [Historical Build 8 installation record](https://github.com/007pig/meshchan/blob/1152097eebd91b13b45d29dbd60cef794d7a5c3d/docs/validation/phase-1e9-install-upgrade.md)
- The release handoff tracks the pending candidate-specific CI evidence and
  publication gates. As of November 22, 2026, this image is unpublished and the
  public download has yet to be checked. GitHub Releases is the planned
  distribution channel. [Meshchan Releases](https://github.com/007pig/meshchan/releases)
