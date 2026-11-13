import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:meshchan_core/meshchan_core.dart';
import 'package:meshcore_link/meshcore_link.dart';

import 'probe_request.dart';

const probeContent = DraftContent(
  title: 'Meshchan platform fixture 🧪',
  body: '草稿 / café / 🌍\nSecond line\r\nLast line\n',
);
const _receiptName = 'meshchan-1d2-receipt.json';

/// One finite worker owns the complete native lifetime. No handles or native
/// exceptions leave it. This is not the future application worker protocol.
Future<Map<String, Object?>> runPlatformProbe(ProbeRequest request) =>
    Isolate.run(
      () => executeFixtureProbe(request),
      debugName: 'meshchan-platform-probe',
    );

Future<Map<String, Object?>> executeFixtureProbe(
  ProbeRequest request, {
  Future<CoreStorage> Function(Directory)? openStorage,
  int Function()? enumeratePorts,
}) async {
  final failures = <Map<String, Object?>>[];
  final closes = <String>[];
  final maintenance = <String>[];
  final result = <String, Object?>{
    'probe': 'meshchan.macos.1d2',
    'mode': request.mode,
    'fixture': request.directory,
    'pid': pid,
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'worker': Isolate.current.debugName,
    'closes': closes,
    'maintenance': maintenance,
    'failures': failures,
    'serialEnumeration': 'NOT_RUN',
  };
  var stage = 'input';
  void fail(Object error) {
    failures.add({
      'stage': stage,
      'code': error is CoreException
          ? error.code.code
          : error is FormatException
          ? 'invalid_fixture'
          : 'probe_failed',
      'cleanupUnconfirmed': error is CoreException && error.cleanupUnconfirmed,
    });
  }

  // Each use always observes maintenance and actual close, including failures.
  Future<bool> use(Future<void> Function(CoreStorage) action) async {
    CoreStorage? storage;
    try {
      storage =
          await (openStorage ??
              (directory) => CoreStorage.open(dataDirectory: directory))(
            Directory(request.directory),
          );
      await action(storage);
    } catch (error) {
      fail(error);
    } finally {
      if (storage != null) {
        stage = 'maintenance';
        try {
          final report = await storage.history.waitForMaintenance();
          maintenance.add(report.state.name);
          if (report.state == HistoryMaintenanceState.failed ||
              storage.history.unacknowledgedFailure != null) {
            fail(
              report.error ??
                  const CoreException(CoreErrorCode.storageWriteFailed),
            );
          }
        } catch (error) {
          fail(error);
        }
        stage = 'close';
        try {
          await storage.close();
          closes.add(storage.state.name);
          if (storage.state != StorageState.closed) {
            fail(
              const CoreException(
                CoreErrorCode.storageWriteFailed,
                cleanupUnconfirmed: true,
              ),
            );
          }
        } catch (error) {
          closes.add(storage.state.name);
          fail(error);
        }
      }
    }
    return failures.isEmpty;
  }

  try {
    // Revalidate even for programmatically constructed requests.
    ProbeRequest.parse([
      '--meshchan-probe=${request.mode}',
      '--fixture=${request.directory}',
    ]);
    if (!Platform.isMacOS && openStorage == null) {
      throw const FormatException('The platform probe requires macOS.');
    }
    final directory = Directory(request.directory);
    final parent = directory.parent;
    if (!parent.existsSync() ||
        parent.resolveSymbolicLinksSync() != parent.path) {
      throw const FormatException(
        'Fixture parent must exist and be canonical.',
      );
    }
    final receipt = File('${directory.path}/$_receiptName');
    final database = File('${directory.path}/meshchan.sqlite');
    late Map<String, dynamic> expected;
    if (request.mode == 'write') {
      if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FormatException('Write requires a new fixture directory.');
      }
      directory.createSync();
      receipt.writeAsStringSync(
        jsonEncode({
          'probe': 'meshchan.macos.1d2',
          'state': 'incomplete',
          'fixture': directory.path,
        }),
        flush: true,
      );
      stage = 'create';
      final created = await use((storage) async {
        final draft = await storage.drafts.create(probeContent);
        expected = {
          'id': draft.id.value,
          'revision': draft.revision,
          'createdAt': draft.createdAt.toIso8601String(),
          'updatedAt': draft.updatedAt.toIso8601String(),
          'bodyUtf8Bytes': draft.bodyUtf8ByteLength,
        };
      });
      if (!created) return {...result, 'passed': false};
    } else {
      if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          directory.resolveSymbolicLinksSync() != directory.path ||
          FileSystemEntity.typeSync(receipt.path, followLinks: false) !=
              FileSystemEntityType.file ||
          receipt.lengthSync() > 4096) {
        throw const FormatException(
          'Read requires an owned, completed fixture.',
        );
      }
      final decoded =
          jsonDecode(receipt.readAsStringSync()) as Map<String, dynamic>;
      if (decoded['probe'] != 'meshchan.macos.1d2' ||
          decoded['state'] != 'closed' ||
          decoded['fixture'] != directory.path) {
        throw const FormatException(
          'Fixture receipt does not confirm closure.',
        );
      }
      expected = decoded['draft'] as Map<String, dynamic>;
      LocalId(expected['id'] as String);
      if (expected['revision'] != 1 ||
          expected['bodyUtf8Bytes'] != probeContent.bodyUtf8ByteLength) {
        throw const FormatException('Invalid fixture facts.');
      }
    }
    // Never allow a missing/wrong reopen path to create a replacement database.
    stage = 'reopen';
    if (FileSystemEntity.typeSync(database.path, followLinks: false) !=
            FileSystemEntityType.file ||
        database.lengthSync() == 0) {
      throw const FormatException('Expected the existing nonempty database.');
    }
    // Invalidate the prior close receipt before acquiring a new owner. A read
    // whose final close is unconfirmed must not authorize a subsequent reopen.
    receipt.writeAsStringSync(
      jsonEncode({
        'probe': 'meshchan.macos.1d2',
        'state': 'incomplete',
        'fixture': directory.path,
        'draft': expected,
      }),
      flush: true,
    );
    await use((storage) async {
      final draft = await storage.drafts.read(
        LocalId(expected['id'] as String),
      );
      if (draft.title != probeContent.title ||
          draft.body != probeContent.body ||
          draft.revision != expected['revision'] ||
          draft.bodyUtf8ByteLength != expected['bodyUtf8Bytes'] ||
          draft.createdAt.toIso8601String() != expected['createdAt'] ||
          draft.updatedAt.toIso8601String() != expected['updatedAt']) {
        throw const FormatException(
          'Persisted draft differs from the closed fixture.',
        );
      }
      result['draft'] = expected;
      result['schema'] = databaseSchemaVersion;
    });
    if (failures.isEmpty) {
      receipt.writeAsStringSync(
        jsonEncode({
          'probe': 'meshchan.macos.1d2',
          'state': 'closed',
          'fixture': directory.path,
          'draft': expected,
        }),
        flush: true,
      );
    }
    if (failures.isEmpty && request.enumerate) {
      stage = 'serial_metadata';
      if (!Platform.isMacOS) {
        throw const FormatException('Metadata check requires macOS.');
      }
      if (enumeratePorts != null) {
        result['portCount'] = enumeratePorts();
        result['warningCount'] = 0;
      } else {
        final ports = SerialPorts().listPorts();
        result['portCount'] = ports.length;
        result['warningCount'] = ports
            .where((port) => port.warning != null)
            .length;
      }
      result['serialEnumeration'] = 'completed';
    }
  } catch (error) {
    fail(error);
  }
  return {...result, 'passed': failures.isEmpty};
}
