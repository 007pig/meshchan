/// Structural transport categories for [ConnectionTarget] values.
enum CompanionTransportKind { usbSerial, tcp, ble }

/// Immutable input for one explicitly selected Companion operation.
///
/// Construction validates local data synchronously without performing I/O.
/// Invalid input throws an [ArgumentError] without the offending value.
/// The result carries no connection state or proof of device availability.
/// Equality compares the concrete type and exact input fields. Use
/// [hashCode] for collections within one isolate and [safeSummary] for
/// diagnostics.
sealed class ConnectionTarget {
  ConnectionTarget._();

  /// The category determined by this target's concrete type.
  CompanionTransportKind get kind;

  /// A category label with no target identifiers or connection state.
  String get safeSummary => kind.name;

  @override
  String toString() => safeSummary;
}

/// An exact path supplied for the serial adapter.
///
/// The path must be nonblank and contain no NUL. It may use any platform's
/// spelling and is preserved verbatim for string comparison. The path is
/// neither resolved nor checked for existence, physical USB attachment, or
/// Companion support.
final class UsbSerialTarget extends ConnectionTarget {
  UsbSerialTarget({required this.portPath}) : super._() {
    if (portPath.trim().isEmpty || portPath.contains('\u0000')) {
      throw ArgumentError('Must be nonblank and contain no NUL.', 'portPath');
    }
  }

  /// The original serial port path.
  final String portPath;

  @override
  CompanionTransportKind get kind => CompanionTransportKind.usbSerial;

  @override
  bool operator ==(Object other) =>
      other is UsbSerialTarget && portPath == other.portPath;

  @override
  int get hashCode => Object.hash(kind, portPath);
}

/// A TCP host and an explicit port in 1..65535.
///
/// Accepts ASCII DNS names (including single labels, Punycode, and an optional
/// final dot), IPv4 literals, and unbracketed IPv6 literals without zone IDs.
/// DNS labels are 1..63 ASCII letters, digits, or internal hyphens, with at
/// most 253 bytes before the optional final dot. Numeric single labels are
/// DNS names. Dotted sequences of numeric labels must be valid IPv4 literals.
/// The host is preserved verbatim. Case, final dots, and alternate IP spellings
/// affect value equality. Construction does not resolve or connect to the host.
final class TcpTarget extends ConnectionTarget {
  TcpTarget({required this.host, required this.port}) : super._() {
    if (!_isValidTcpHost(host)) {
      throw ArgumentError(
        'Must be an ASCII DNS name, IPv4 address, or bare IPv6 address '
            'without a zone ID. Specify the port separately.',
        'host',
      );
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError('Must be between 1 and 65535.', 'port');
    }
  }

  /// The original host spelling.
  final String host;

  /// The independently supplied TCP port.
  final int port;

  @override
  CompanionTransportKind get kind => CompanionTransportKind.tcp;

  @override
  bool operator ==(Object other) =>
      other is TcpTarget && host == other.host && port == other.port;

  @override
  int get hashCode => Object.hash(kind, host, port);
}

/// Opaque selection data supplied by the host for a BLE operation.
///
/// The selection must be nonblank and contain no surrounding whitespace or
/// control characters. The original string is compared verbatim. The host
/// owns the selection's scope, lifetime, and mapping to a peripheral. Value
/// equality conveys no authenticated identity or guarantee that the selection
/// is still valid.
final class BleTarget extends ConnectionTarget {
  BleTarget({required this.selectionId}) : super._() {
    if (selectionId.isEmpty ||
        selectionId != selectionId.trim() ||
        _controlCharacter.hasMatch(selectionId)) {
      throw ArgumentError(
        'Must be nonblank and contain no surrounding whitespace or control '
            'characters.',
        'selectionId',
      );
    }
  }

  /// The original host-scoped selection identifier.
  final String selectionId;

  @override
  CompanionTransportKind get kind => CompanionTransportKind.ble;

  @override
  bool operator ==(Object other) =>
      other is BleTarget && selectionId == other.selectionId;

  @override
  int get hashCode => Object.hash(kind, selectionId);
}

final _controlCharacter = RegExp(r'[\x00-\x1F\x7F-\x9F]');
final _nonIpv4Character = RegExp(r'[^0-9.]');
final _dnsLabel = RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$');

bool _isValidTcpHost(String host) {
  try {
    if (host.contains(':')) {
      Uri.parseIPv6Address(host);
      return true;
    }
    final name = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    if (name.contains('.') && !_nonIpv4Character.hasMatch(name)) {
      Uri.parseIPv4Address(host);
      return true;
    }
    return name.length <= 253 && name.split('.').every(_dnsLabel.hasMatch);
  } on FormatException {
    // The standard parser's exception can contain the original address.
    return false;
  } on RangeError {
    // Dart 3.14 can hit a buffer index error on overfull compressed IPv6.
    return false;
  }
}
