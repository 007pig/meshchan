import 'dart:async';
import 'dart:typed_data';

import 'package:meshcore_link/meshcore_link.dart';
import 'package:meshcore_link/src/transport/companion_transport_factory.dart'
    show companionTransportFactoryWithUsbBuilder;
import 'package:test/test.dart';

import 'support/fake_companion_transport.dart';

void main() {
  test('USB delegation preserves the exact path and each host policy', () {
    const path = '  /dev/meshchan-factory-test  ';
    final target = UsbSerialTarget(portPath: path);
    final calls = <(String, bool, FakeCompanionTransport)>[];

    CompanionTransport buildUsb(
      String portPath, {
      required bool appCompletionQueries,
    }) {
      final transport = FakeCompanionTransport();
      addTearDown(() async {
        if (transport.listenCount == 0) {
          unawaited(transport.frames.drain<void>());
        }
        await transport.finishInput();
        await transport.close();
      });
      calls.add((portPath, appCompletionQueries, transport));
      return transport;
    }

    final cliFactory = companionTransportFactoryWithUsbBuilder(
      appCompletionQueries: false,
      createUsbTransport: buildUsb,
    );
    final appFactory = companionTransportFactoryWithUsbBuilder(
      appCompletionQueries: true,
      createUsbTransport: buildUsb,
    );

    expect(calls, isEmpty);
    final selections = [
      (cliFactory, false),
      (appFactory, true),
      (cliFactory, false),
      (appFactory, true),
    ];
    final results = Set<CompanionTransport>.identity();
    for (final (index, (factory, expectedPolicy)) in selections.indexed) {
      final result = factory(target);
      expect(calls, hasLength(index + 1));
      final (actualPath, actualPolicy, builtTransport) = calls.last;
      expect(actualPath, path);
      expect(actualPolicy, expectedPolicy);
      expect(result, same(builtTransport));
      expect(builtTransport.calls, isEmpty);
      expect(results.add(result), isTrue);
    }
  });

  test('default USB transports have independent frames and closure', () async {
    final CompanionTransportFactory factory = createCompanionTransportFactory(
      appCompletionQueries: false,
    );
    final target = UsbSerialTarget(portPath: 'factory-test');
    final equalTarget = UsbSerialTarget(portPath: target.portPath);
    expect(equalTarget, target);
    expect(equalTarget, isNot(same(target)));

    final transports = Set<CompanionTransport>.identity();
    final streams = Set<Stream<Uint8List>>.identity();
    CompanionTransport create(ConnectionTarget selected) {
      final transport = factory(selected);
      addTearDown(transport.close);
      expect(transports.add(transport), isTrue);
      expect(streams.add(transport.frames), isTrue);
      return transport;
    }

    final first = create(target);
    final second = create(target);
    create(equalTarget);

    final firstDone = first.frames.drain<void>();
    var secondEnded = false;
    final secondDone = second.frames.drain<void>().then((_) {
      secondEnded = true;
    });
    await first.close();
    await firstDone;
    expect(secondEnded, isFalse);

    await second.close();
    await secondDone;
    create(target);
  });

  test(
    'a default USB transport can be closed unopened and without a listener',
    () async {
      final factory = createCompanionTransportFactory(
        appCompletionQueries: true,
      );
      final transport = factory(UsbSerialTarget(portPath: 'factory-test'));
      final closing = transport.close();
      expect(transport.close(), same(closing));
      await closing;
      expect(transport.close(), same(closing));
    },
  );

  test('default USB rejects open before frame subscription', () async {
    final factory = createCompanionTransportFactory(appCompletionQueries: true);
    final transport = factory(UsbSerialTarget(portPath: 'factory-test'));
    addTearDown(transport.close);

    await expectLater(
      transport.open(),
      throwsA(
        isStateError.having(
          (error) => error.message,
          'message',
          'Subscribe to frames before open().',
        ),
      ),
    );
  });

  test('TCP and BLE fail synchronously with safe kind-specific errors', () {
    const host = 'Factory-Private-Host.test.';
    const port = 53179;
    const selection = 'Factory private café token';
    final factories = [
      createCompanionTransportFactory(appCompletionQueries: false),
      companionTransportFactoryWithUsbBuilder(
        appCompletionQueries: true,
        createUsbTransport: (_, {required appCompletionQueries}) =>
            fail('Unsupported targets must never invoke the USB builder.'),
      ),
    ];
    final targets = [
      (TcpTarget(host: host, port: port), CompanionTransportKind.tcp),
      (BleTarget(selectionId: selection), CompanionTransportKind.ble),
    ];

    expect(() {
      for (final factory in factories) {
        for (final (target, kind) in targets) {
          expect(
            () {
              final transport = factory(target);
              addTearDown(transport.close);
            },
            throwsA(
              isA<UnsupportedCompanionTransportException>()
                  .having((error) => error.kind, 'kind', kind)
                  .having(
                    (error) => '$error',
                    'safe text',
                    allOf(
                      contains('This factory has no ${kind.name} adapter.'),
                      isNot(
                        anyOf(
                          contains(host),
                          contains('$port'),
                          contains(selection),
                        ),
                      ),
                    ),
                  ),
            ),
          );
        }
      }
    }, prints(isEmpty));
  });

  test('a USB builder failure propagates unchanged after one attempt', () {
    final failure = StateError('Synthetic USB builder failure.');
    var calls = 0;
    final factory = companionTransportFactoryWithUsbBuilder(
      appCompletionQueries: false,
      createUsbTransport: (_, {required appCompletionQueries}) {
        calls++;
        throw failure;
      },
    );

    expect(() {
      final transport = factory(UsbSerialTarget(portPath: 'factory-test'));
      addTearDown(transport.close);
    }, throwsA(same(failure)));
    expect(calls, 1);
  });
}
