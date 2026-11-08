# Meshchan

Meshchan is an open-source decentralized content application based on MeshCore. Its long-term direction is Flutter and Dart, with a reusable communication core that stays independent of Flutter. Development starts with a command-line diagnostic tool before adding a user interface.

The current implementation covers **Phase 1 / 1A / Step 1: project initialization and the development environment**. It includes a native Dart Pub Workspace, CLI help and version output, formatting and analysis checks, unit tests, and a CI workflow.

| Package | Responsibility and current status |
| --- | --- |
| `packages/meshcore_link` | Reusable communication core in pure Dart; currently contains only the public library entry point. |
| `apps/meshctl` | Command-line diagnostic tool skeleton with help, application version output, and argument error handling. |

## Quick start

On this machine, use the Homebrew-managed Flutter SDK and its bundled Dart SDK:

```bash
export PATH="/opt/homebrew/share/flutter/bin:$PATH"

# Run from the project root.
dart pub get --enforce-lockfile
cd apps/meshctl
dart run bin/meshctl.dart --help
dart run bin/meshctl.dart --version
```

Running without arguments or with `-h` also displays help. Unknown options and positional arguments produce an error on stderr and exit with code `64`. The current application version is `0.1.0-dev.1`.

**Device connections are not implemented.** Device discovery, frame encoding and decoding, sessions, LoRa communication, database features, and the Flutter UI are also outside the current scope. No radio hardware is required.

See the [Developer Guide](docs/development.md) for the validated SDK baseline, complete verification commands, project language conventions, and the SDK update process.
