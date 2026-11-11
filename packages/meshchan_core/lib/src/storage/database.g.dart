// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class StoredDrafts extends Table with TableInfo<StoredDrafts, StoredDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StoredDrafts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 32 AND id NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtUsMeta = const VerificationMeta(
    'createdAtUs',
  );
  late final GeneratedColumn<int> createdAtUs = GeneratedColumn<int>(
    'created_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(created_at_us) = \'integer\')',
  );
  static const VerificationMeta _updatedAtUsMeta = const VerificationMeta(
    'updatedAtUs',
  );
  late final GeneratedColumn<int> updatedAtUs = GeneratedColumn<int>(
    'updated_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(updated_at_us) = \'integer\')',
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (typeof(revision) = \'integer\' AND revision > 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    body,
    createdAtUs,
    updatedAtUs,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('created_at_us')) {
      context.handle(
        _createdAtUsMeta,
        createdAtUs.isAcceptableOrUnknown(
          data['created_at_us']!,
          _createdAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUsMeta);
    }
    if (data.containsKey('updated_at_us')) {
      context.handle(
        _updatedAtUsMeta,
        updatedAtUs.isAcceptableOrUnknown(
          data['updated_at_us']!,
          _updatedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUsMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredDraft(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      createdAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_us'],
      )!,
      updatedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_us'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  StoredDrafts createAlias(String alias) {
    return StoredDrafts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StoredDraft extends DataClass implements Insertable<StoredDraft> {
  final String id;
  final String title;
  final String body;
  final int createdAtUs;
  final int updatedAtUs;
  final int revision;
  const StoredDraft({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAtUs,
    required this.updatedAtUs,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['created_at_us'] = Variable<int>(createdAtUs);
    map['updated_at_us'] = Variable<int>(updatedAtUs);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  StoredDraftsCompanion toCompanion(bool nullToAbsent) {
    return StoredDraftsCompanion(
      id: Value(id),
      title: Value(title),
      body: Value(body),
      createdAtUs: Value(createdAtUs),
      updatedAtUs: Value(updatedAtUs),
      revision: Value(revision),
    );
  }

  factory StoredDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredDraft(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      createdAtUs: serializer.fromJson<int>(json['created_at_us']),
      updatedAtUs: serializer.fromJson<int>(json['updated_at_us']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'created_at_us': serializer.toJson<int>(createdAtUs),
      'updated_at_us': serializer.toJson<int>(updatedAtUs),
      'revision': serializer.toJson<int>(revision),
    };
  }

  StoredDraft copyWith({
    String? id,
    String? title,
    String? body,
    int? createdAtUs,
    int? updatedAtUs,
    int? revision,
  }) => StoredDraft(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    createdAtUs: createdAtUs ?? this.createdAtUs,
    updatedAtUs: updatedAtUs ?? this.updatedAtUs,
    revision: revision ?? this.revision,
  );
  StoredDraft copyWithCompanion(StoredDraftsCompanion data) {
    return StoredDraft(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      createdAtUs: data.createdAtUs.present
          ? data.createdAtUs.value
          : this.createdAtUs,
      updatedAtUs: data.updatedAtUs.present
          ? data.updatedAtUs.value
          : this.updatedAtUs,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredDraft(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('createdAtUs: $createdAtUs, ')
          ..write('updatedAtUs: $updatedAtUs, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, body, createdAtUs, updatedAtUs, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredDraft &&
          other.id == this.id &&
          other.title == this.title &&
          other.body == this.body &&
          other.createdAtUs == this.createdAtUs &&
          other.updatedAtUs == this.updatedAtUs &&
          other.revision == this.revision);
}

class StoredDraftsCompanion extends UpdateCompanion<StoredDraft> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> body;
  final Value<int> createdAtUs;
  final Value<int> updatedAtUs;
  final Value<int> revision;
  final Value<int> rowid;
  const StoredDraftsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.createdAtUs = const Value.absent(),
    this.updatedAtUs = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredDraftsCompanion.insert({
    required String id,
    required String title,
    required String body,
    required int createdAtUs,
    required int updatedAtUs,
    required int revision,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       body = Value(body),
       createdAtUs = Value(createdAtUs),
       updatedAtUs = Value(updatedAtUs),
       revision = Value(revision);
  static Insertable<StoredDraft> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? body,
    Expression<int>? createdAtUs,
    Expression<int>? updatedAtUs,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (createdAtUs != null) 'created_at_us': createdAtUs,
      if (updatedAtUs != null) 'updated_at_us': updatedAtUs,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredDraftsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? body,
    Value<int>? createdAtUs,
    Value<int>? updatedAtUs,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return StoredDraftsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAtUs: createdAtUs ?? this.createdAtUs,
      updatedAtUs: updatedAtUs ?? this.updatedAtUs,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (createdAtUs.present) {
      map['created_at_us'] = Variable<int>(createdAtUs.value);
    }
    if (updatedAtUs.present) {
      map['updated_at_us'] = Variable<int>(updatedAtUs.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredDraftsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('createdAtUs: $createdAtUs, ')
          ..write('updatedAtUs: $updatedAtUs, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class StoredProfiles extends Table
    with TableInfo<StoredProfiles, StoredProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StoredProfiles(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 32 AND id NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(trim(name)) > 0)',
  );
  static const VerificationMeta _portHintMeta = const VerificationMeta(
    'portHint',
  );
  late final GeneratedColumn<String> portHint = GeneratedColumn<String>(
    'port_hint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (operation IN (\'send\', \'listen\', \'ping\', \'respond\'))',
  );
  static const VerificationMeta _parametersJsonMeta = const VerificationMeta(
    'parametersJson',
  );
  late final GeneratedColumn<String> parametersJson = GeneratedColumn<String>(
    'parameters_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _updatedAtUsMeta = const VerificationMeta(
    'updatedAtUs',
  );
  late final GeneratedColumn<int> updatedAtUs = GeneratedColumn<int>(
    'updated_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(updated_at_us) = \'integer\')',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    portHint,
    operation,
    parametersJson,
    updatedAtUs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('port_hint')) {
      context.handle(
        _portHintMeta,
        portHint.isAcceptableOrUnknown(data['port_hint']!, _portHintMeta),
      );
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('parameters_json')) {
      context.handle(
        _parametersJsonMeta,
        parametersJson.isAcceptableOrUnknown(
          data['parameters_json']!,
          _parametersJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parametersJsonMeta);
    }
    if (data.containsKey('updated_at_us')) {
      context.handle(
        _updatedAtUsMeta,
        updatedAtUs.isAcceptableOrUnknown(
          data['updated_at_us']!,
          _updatedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      portHint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}port_hint'],
      ),
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      parametersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parameters_json'],
      )!,
      updatedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_us'],
      )!,
    );
  }

  @override
  StoredProfiles createAlias(String alias) {
    return StoredProfiles(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StoredProfile extends DataClass implements Insertable<StoredProfile> {
  final String id;
  final String name;
  final String? portHint;
  final String operation;
  final String parametersJson;
  final int updatedAtUs;
  const StoredProfile({
    required this.id,
    required this.name,
    this.portHint,
    required this.operation,
    required this.parametersJson,
    required this.updatedAtUs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || portHint != null) {
      map['port_hint'] = Variable<String>(portHint);
    }
    map['operation'] = Variable<String>(operation);
    map['parameters_json'] = Variable<String>(parametersJson);
    map['updated_at_us'] = Variable<int>(updatedAtUs);
    return map;
  }

  StoredProfilesCompanion toCompanion(bool nullToAbsent) {
    return StoredProfilesCompanion(
      id: Value(id),
      name: Value(name),
      portHint: portHint == null && nullToAbsent
          ? const Value.absent()
          : Value(portHint),
      operation: Value(operation),
      parametersJson: Value(parametersJson),
      updatedAtUs: Value(updatedAtUs),
    );
  }

  factory StoredProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredProfile(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      portHint: serializer.fromJson<String?>(json['port_hint']),
      operation: serializer.fromJson<String>(json['operation']),
      parametersJson: serializer.fromJson<String>(json['parameters_json']),
      updatedAtUs: serializer.fromJson<int>(json['updated_at_us']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'port_hint': serializer.toJson<String?>(portHint),
      'operation': serializer.toJson<String>(operation),
      'parameters_json': serializer.toJson<String>(parametersJson),
      'updated_at_us': serializer.toJson<int>(updatedAtUs),
    };
  }

  StoredProfile copyWith({
    String? id,
    String? name,
    Value<String?> portHint = const Value.absent(),
    String? operation,
    String? parametersJson,
    int? updatedAtUs,
  }) => StoredProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    portHint: portHint.present ? portHint.value : this.portHint,
    operation: operation ?? this.operation,
    parametersJson: parametersJson ?? this.parametersJson,
    updatedAtUs: updatedAtUs ?? this.updatedAtUs,
  );
  StoredProfile copyWithCompanion(StoredProfilesCompanion data) {
    return StoredProfile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      portHint: data.portHint.present ? data.portHint.value : this.portHint,
      operation: data.operation.present ? data.operation.value : this.operation,
      parametersJson: data.parametersJson.present
          ? data.parametersJson.value
          : this.parametersJson,
      updatedAtUs: data.updatedAtUs.present
          ? data.updatedAtUs.value
          : this.updatedAtUs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredProfile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('portHint: $portHint, ')
          ..write('operation: $operation, ')
          ..write('parametersJson: $parametersJson, ')
          ..write('updatedAtUs: $updatedAtUs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, portHint, operation, parametersJson, updatedAtUs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredProfile &&
          other.id == this.id &&
          other.name == this.name &&
          other.portHint == this.portHint &&
          other.operation == this.operation &&
          other.parametersJson == this.parametersJson &&
          other.updatedAtUs == this.updatedAtUs);
}

class StoredProfilesCompanion extends UpdateCompanion<StoredProfile> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> portHint;
  final Value<String> operation;
  final Value<String> parametersJson;
  final Value<int> updatedAtUs;
  final Value<int> rowid;
  const StoredProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.portHint = const Value.absent(),
    this.operation = const Value.absent(),
    this.parametersJson = const Value.absent(),
    this.updatedAtUs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredProfilesCompanion.insert({
    required String id,
    required String name,
    this.portHint = const Value.absent(),
    required String operation,
    required String parametersJson,
    required int updatedAtUs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       operation = Value(operation),
       parametersJson = Value(parametersJson),
       updatedAtUs = Value(updatedAtUs);
  static Insertable<StoredProfile> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? portHint,
    Expression<String>? operation,
    Expression<String>? parametersJson,
    Expression<int>? updatedAtUs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (portHint != null) 'port_hint': portHint,
      if (operation != null) 'operation': operation,
      if (parametersJson != null) 'parameters_json': parametersJson,
      if (updatedAtUs != null) 'updated_at_us': updatedAtUs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? portHint,
    Value<String>? operation,
    Value<String>? parametersJson,
    Value<int>? updatedAtUs,
    Value<int>? rowid,
  }) {
    return StoredProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      portHint: portHint ?? this.portHint,
      operation: operation ?? this.operation,
      parametersJson: parametersJson ?? this.parametersJson,
      updatedAtUs: updatedAtUs ?? this.updatedAtUs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (portHint.present) {
      map['port_hint'] = Variable<String>(portHint.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (parametersJson.present) {
      map['parameters_json'] = Variable<String>(parametersJson.value);
    }
    if (updatedAtUs.present) {
      map['updated_at_us'] = Variable<int>(updatedAtUs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('portHint: $portHint, ')
          ..write('operation: $operation, ')
          ..write('parametersJson: $parametersJson, ')
          ..write('updatedAtUs: $updatedAtUs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class StoredSettings extends Table
    with TableInfo<StoredSettings, StoredSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StoredSettings(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (singleton = 1)',
  );
  static const VerificationMeta _defaultProfileIdMeta = const VerificationMeta(
    'defaultProfileId',
  );
  late final GeneratedColumn<String> defaultProfileId = GeneratedColumn<String>(
    'default_profile_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'REFERENCES stored_profiles(id)ON DELETE SET NULL',
  );
  static const VerificationMeta _diagnosticHistoryLimitMeta =
      const VerificationMeta('diagnosticHistoryLimit');
  late final GeneratedColumn<int> diagnosticHistoryLimit = GeneratedColumn<int>(
    'diagnostic_history_limit',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(diagnostic_history_limit) = \'integer\' AND diagnostic_history_limit BETWEEN 1 AND 100000)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    singleton,
    defaultProfileId,
    diagnosticHistoryLimit,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('default_profile_id')) {
      context.handle(
        _defaultProfileIdMeta,
        defaultProfileId.isAcceptableOrUnknown(
          data['default_profile_id']!,
          _defaultProfileIdMeta,
        ),
      );
    }
    if (data.containsKey('diagnostic_history_limit')) {
      context.handle(
        _diagnosticHistoryLimitMeta,
        diagnosticHistoryLimit.isAcceptableOrUnknown(
          data['diagnostic_history_limit']!,
          _diagnosticHistoryLimitMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_diagnosticHistoryLimitMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  StoredSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredSetting(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      defaultProfileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_profile_id'],
      ),
      diagnosticHistoryLimit: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}diagnostic_history_limit'],
      )!,
    );
  }

  @override
  StoredSettings createAlias(String alias) {
    return StoredSettings(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StoredSetting extends DataClass implements Insertable<StoredSetting> {
  final int singleton;
  final String? defaultProfileId;
  final int diagnosticHistoryLimit;
  const StoredSetting({
    required this.singleton,
    this.defaultProfileId,
    required this.diagnosticHistoryLimit,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    if (!nullToAbsent || defaultProfileId != null) {
      map['default_profile_id'] = Variable<String>(defaultProfileId);
    }
    map['diagnostic_history_limit'] = Variable<int>(diagnosticHistoryLimit);
    return map;
  }

  StoredSettingsCompanion toCompanion(bool nullToAbsent) {
    return StoredSettingsCompanion(
      singleton: Value(singleton),
      defaultProfileId: defaultProfileId == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultProfileId),
      diagnosticHistoryLimit: Value(diagnosticHistoryLimit),
    );
  }

  factory StoredSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredSetting(
      singleton: serializer.fromJson<int>(json['singleton']),
      defaultProfileId: serializer.fromJson<String?>(
        json['default_profile_id'],
      ),
      diagnosticHistoryLimit: serializer.fromJson<int>(
        json['diagnostic_history_limit'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'default_profile_id': serializer.toJson<String?>(defaultProfileId),
      'diagnostic_history_limit': serializer.toJson<int>(
        diagnosticHistoryLimit,
      ),
    };
  }

  StoredSetting copyWith({
    int? singleton,
    Value<String?> defaultProfileId = const Value.absent(),
    int? diagnosticHistoryLimit,
  }) => StoredSetting(
    singleton: singleton ?? this.singleton,
    defaultProfileId: defaultProfileId.present
        ? defaultProfileId.value
        : this.defaultProfileId,
    diagnosticHistoryLimit:
        diagnosticHistoryLimit ?? this.diagnosticHistoryLimit,
  );
  StoredSetting copyWithCompanion(StoredSettingsCompanion data) {
    return StoredSetting(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      defaultProfileId: data.defaultProfileId.present
          ? data.defaultProfileId.value
          : this.defaultProfileId,
      diagnosticHistoryLimit: data.diagnosticHistoryLimit.present
          ? data.diagnosticHistoryLimit.value
          : this.diagnosticHistoryLimit,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredSetting(')
          ..write('singleton: $singleton, ')
          ..write('defaultProfileId: $defaultProfileId, ')
          ..write('diagnosticHistoryLimit: $diagnosticHistoryLimit')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(singleton, defaultProfileId, diagnosticHistoryLimit);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredSetting &&
          other.singleton == this.singleton &&
          other.defaultProfileId == this.defaultProfileId &&
          other.diagnosticHistoryLimit == this.diagnosticHistoryLimit);
}

class StoredSettingsCompanion extends UpdateCompanion<StoredSetting> {
  final Value<int> singleton;
  final Value<String?> defaultProfileId;
  final Value<int> diagnosticHistoryLimit;
  const StoredSettingsCompanion({
    this.singleton = const Value.absent(),
    this.defaultProfileId = const Value.absent(),
    this.diagnosticHistoryLimit = const Value.absent(),
  });
  StoredSettingsCompanion.insert({
    this.singleton = const Value.absent(),
    this.defaultProfileId = const Value.absent(),
    required int diagnosticHistoryLimit,
  }) : diagnosticHistoryLimit = Value(diagnosticHistoryLimit);
  static Insertable<StoredSetting> custom({
    Expression<int>? singleton,
    Expression<String>? defaultProfileId,
    Expression<int>? diagnosticHistoryLimit,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (defaultProfileId != null) 'default_profile_id': defaultProfileId,
      if (diagnosticHistoryLimit != null)
        'diagnostic_history_limit': diagnosticHistoryLimit,
    });
  }

  StoredSettingsCompanion copyWith({
    Value<int>? singleton,
    Value<String?>? defaultProfileId,
    Value<int>? diagnosticHistoryLimit,
  }) {
    return StoredSettingsCompanion(
      singleton: singleton ?? this.singleton,
      defaultProfileId: defaultProfileId ?? this.defaultProfileId,
      diagnosticHistoryLimit:
          diagnosticHistoryLimit ?? this.diagnosticHistoryLimit,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (defaultProfileId.present) {
      map['default_profile_id'] = Variable<String>(defaultProfileId.value);
    }
    if (diagnosticHistoryLimit.present) {
      map['diagnostic_history_limit'] = Variable<int>(
        diagnosticHistoryLimit.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredSettingsCompanion(')
          ..write('singleton: $singleton, ')
          ..write('defaultProfileId: $defaultProfileId, ')
          ..write('diagnosticHistoryLimit: $diagnosticHistoryLimit')
          ..write(')'))
        .toString();
  }
}

class StoredRuns extends Table with TableInfo<StoredRuns, StoredRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  StoredRuns(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(run_id) = 32 AND run_id NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (operation IN (\'send\', \'listen\', \'ping\', \'respond\'))',
  );
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (profile_id IS NULL OR(length(profile_id) = 32 AND profile_id NOT GLOB \'*[^0-9a-f]*\'))',
  );
  static const VerificationMeta _configurationJsonMeta = const VerificationMeta(
    'configurationJson',
  );
  late final GeneratedColumn<String> configurationJson =
      GeneratedColumn<String>(
        'configuration_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      );
  static const VerificationMeta _preparedAtUsMeta = const VerificationMeta(
    'preparedAtUs',
  );
  late final GeneratedColumn<int> preparedAtUs = GeneratedColumn<int>(
    'prepared_at_us',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(prepared_at_us) = \'integer\')',
  );
  static const VerificationMeta _logicalEndedAtUsMeta = const VerificationMeta(
    'logicalEndedAtUs',
  );
  late final GeneratedColumn<int> logicalEndedAtUs = GeneratedColumn<int>(
    'logical_ended_at_us',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (logical_ended_at_us IS NULL OR typeof(logical_ended_at_us) = \'integer\')',
  );
  static const VerificationMeta _recordStateMeta = const VerificationMeta(
    'recordState',
  );
  late final GeneratedColumn<String> recordState = GeneratedColumn<String>(
    'record_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (record_state IN (\'prepared\', \'settled\', \'recovered_archived\'))',
  );
  static const VerificationMeta _resultJsonMeta = const VerificationMeta(
    'resultJson',
  );
  late final GeneratedColumn<String> resultJson = GeneratedColumn<String>(
    'result_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _cleanupJsonMeta = const VerificationMeta(
    'cleanupJson',
  );
  late final GeneratedColumn<String> cleanupJson = GeneratedColumn<String>(
    'cleanup_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _recoveredAtUsMeta = const VerificationMeta(
    'recoveredAtUs',
  );
  late final GeneratedColumn<int> recoveredAtUs = GeneratedColumn<int>(
    'recovered_at_us',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (recovered_at_us IS NULL OR typeof(recovered_at_us) = \'integer\')',
  );
  static const VerificationMeta _recoveryReasonMeta = const VerificationMeta(
    'recoveryReason',
  );
  late final GeneratedColumn<String> recoveryReason = GeneratedColumn<String>(
    'recovery_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (recovery_reason IS NULL OR recovery_reason IN (\'interrupted\', \'cleanup_unconfirmed\'))',
  );
  static const VerificationMeta _summaryFormatVersionMeta =
      const VerificationMeta('summaryFormatVersion');
  late final GeneratedColumn<int> summaryFormatVersion = GeneratedColumn<int>(
    'summary_format_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (typeof(summary_format_version) = \'integer\' AND summary_format_version > 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    runId,
    operation,
    appVersion,
    profileId,
    configurationJson,
    preparedAtUs,
    logicalEndedAtUs,
    recordState,
    resultJson,
    cleanupJson,
    recoveredAtUs,
    recoveryReason,
    summaryFormatVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredRun> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_appVersionMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    if (data.containsKey('configuration_json')) {
      context.handle(
        _configurationJsonMeta,
        configurationJson.isAcceptableOrUnknown(
          data['configuration_json']!,
          _configurationJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_configurationJsonMeta);
    }
    if (data.containsKey('prepared_at_us')) {
      context.handle(
        _preparedAtUsMeta,
        preparedAtUs.isAcceptableOrUnknown(
          data['prepared_at_us']!,
          _preparedAtUsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_preparedAtUsMeta);
    }
    if (data.containsKey('logical_ended_at_us')) {
      context.handle(
        _logicalEndedAtUsMeta,
        logicalEndedAtUs.isAcceptableOrUnknown(
          data['logical_ended_at_us']!,
          _logicalEndedAtUsMeta,
        ),
      );
    }
    if (data.containsKey('record_state')) {
      context.handle(
        _recordStateMeta,
        recordState.isAcceptableOrUnknown(
          data['record_state']!,
          _recordStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordStateMeta);
    }
    if (data.containsKey('result_json')) {
      context.handle(
        _resultJsonMeta,
        resultJson.isAcceptableOrUnknown(data['result_json']!, _resultJsonMeta),
      );
    }
    if (data.containsKey('cleanup_json')) {
      context.handle(
        _cleanupJsonMeta,
        cleanupJson.isAcceptableOrUnknown(
          data['cleanup_json']!,
          _cleanupJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cleanupJsonMeta);
    }
    if (data.containsKey('recovered_at_us')) {
      context.handle(
        _recoveredAtUsMeta,
        recoveredAtUs.isAcceptableOrUnknown(
          data['recovered_at_us']!,
          _recoveredAtUsMeta,
        ),
      );
    }
    if (data.containsKey('recovery_reason')) {
      context.handle(
        _recoveryReasonMeta,
        recoveryReason.isAcceptableOrUnknown(
          data['recovery_reason']!,
          _recoveryReasonMeta,
        ),
      );
    }
    if (data.containsKey('summary_format_version')) {
      context.handle(
        _summaryFormatVersionMeta,
        summaryFormatVersion.isAcceptableOrUnknown(
          data['summary_format_version']!,
          _summaryFormatVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_summaryFormatVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {runId};
  @override
  StoredRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredRun(
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      appVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_version'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      ),
      configurationJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}configuration_json'],
      )!,
      preparedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}prepared_at_us'],
      )!,
      logicalEndedAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logical_ended_at_us'],
      ),
      recordState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_state'],
      )!,
      resultJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_json'],
      ),
      cleanupJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cleanup_json'],
      )!,
      recoveredAtUs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recovered_at_us'],
      ),
      recoveryReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recovery_reason'],
      ),
      summaryFormatVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}summary_format_version'],
      )!,
    );
  }

  @override
  StoredRuns createAlias(String alias) {
    return StoredRuns(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class StoredRun extends DataClass implements Insertable<StoredRun> {
  final String runId;
  final String operation;
  final String appVersion;
  final String? profileId;
  final String configurationJson;
  final int preparedAtUs;
  final int? logicalEndedAtUs;
  final String recordState;
  final String? resultJson;
  final String cleanupJson;
  final int? recoveredAtUs;
  final String? recoveryReason;
  final int summaryFormatVersion;
  const StoredRun({
    required this.runId,
    required this.operation,
    required this.appVersion,
    this.profileId,
    required this.configurationJson,
    required this.preparedAtUs,
    this.logicalEndedAtUs,
    required this.recordState,
    this.resultJson,
    required this.cleanupJson,
    this.recoveredAtUs,
    this.recoveryReason,
    required this.summaryFormatVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['run_id'] = Variable<String>(runId);
    map['operation'] = Variable<String>(operation);
    map['app_version'] = Variable<String>(appVersion);
    if (!nullToAbsent || profileId != null) {
      map['profile_id'] = Variable<String>(profileId);
    }
    map['configuration_json'] = Variable<String>(configurationJson);
    map['prepared_at_us'] = Variable<int>(preparedAtUs);
    if (!nullToAbsent || logicalEndedAtUs != null) {
      map['logical_ended_at_us'] = Variable<int>(logicalEndedAtUs);
    }
    map['record_state'] = Variable<String>(recordState);
    if (!nullToAbsent || resultJson != null) {
      map['result_json'] = Variable<String>(resultJson);
    }
    map['cleanup_json'] = Variable<String>(cleanupJson);
    if (!nullToAbsent || recoveredAtUs != null) {
      map['recovered_at_us'] = Variable<int>(recoveredAtUs);
    }
    if (!nullToAbsent || recoveryReason != null) {
      map['recovery_reason'] = Variable<String>(recoveryReason);
    }
    map['summary_format_version'] = Variable<int>(summaryFormatVersion);
    return map;
  }

  StoredRunsCompanion toCompanion(bool nullToAbsent) {
    return StoredRunsCompanion(
      runId: Value(runId),
      operation: Value(operation),
      appVersion: Value(appVersion),
      profileId: profileId == null && nullToAbsent
          ? const Value.absent()
          : Value(profileId),
      configurationJson: Value(configurationJson),
      preparedAtUs: Value(preparedAtUs),
      logicalEndedAtUs: logicalEndedAtUs == null && nullToAbsent
          ? const Value.absent()
          : Value(logicalEndedAtUs),
      recordState: Value(recordState),
      resultJson: resultJson == null && nullToAbsent
          ? const Value.absent()
          : Value(resultJson),
      cleanupJson: Value(cleanupJson),
      recoveredAtUs: recoveredAtUs == null && nullToAbsent
          ? const Value.absent()
          : Value(recoveredAtUs),
      recoveryReason: recoveryReason == null && nullToAbsent
          ? const Value.absent()
          : Value(recoveryReason),
      summaryFormatVersion: Value(summaryFormatVersion),
    );
  }

  factory StoredRun.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredRun(
      runId: serializer.fromJson<String>(json['run_id']),
      operation: serializer.fromJson<String>(json['operation']),
      appVersion: serializer.fromJson<String>(json['app_version']),
      profileId: serializer.fromJson<String?>(json['profile_id']),
      configurationJson: serializer.fromJson<String>(
        json['configuration_json'],
      ),
      preparedAtUs: serializer.fromJson<int>(json['prepared_at_us']),
      logicalEndedAtUs: serializer.fromJson<int?>(json['logical_ended_at_us']),
      recordState: serializer.fromJson<String>(json['record_state']),
      resultJson: serializer.fromJson<String?>(json['result_json']),
      cleanupJson: serializer.fromJson<String>(json['cleanup_json']),
      recoveredAtUs: serializer.fromJson<int?>(json['recovered_at_us']),
      recoveryReason: serializer.fromJson<String?>(json['recovery_reason']),
      summaryFormatVersion: serializer.fromJson<int>(
        json['summary_format_version'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'run_id': serializer.toJson<String>(runId),
      'operation': serializer.toJson<String>(operation),
      'app_version': serializer.toJson<String>(appVersion),
      'profile_id': serializer.toJson<String?>(profileId),
      'configuration_json': serializer.toJson<String>(configurationJson),
      'prepared_at_us': serializer.toJson<int>(preparedAtUs),
      'logical_ended_at_us': serializer.toJson<int?>(logicalEndedAtUs),
      'record_state': serializer.toJson<String>(recordState),
      'result_json': serializer.toJson<String?>(resultJson),
      'cleanup_json': serializer.toJson<String>(cleanupJson),
      'recovered_at_us': serializer.toJson<int?>(recoveredAtUs),
      'recovery_reason': serializer.toJson<String?>(recoveryReason),
      'summary_format_version': serializer.toJson<int>(summaryFormatVersion),
    };
  }

  StoredRun copyWith({
    String? runId,
    String? operation,
    String? appVersion,
    Value<String?> profileId = const Value.absent(),
    String? configurationJson,
    int? preparedAtUs,
    Value<int?> logicalEndedAtUs = const Value.absent(),
    String? recordState,
    Value<String?> resultJson = const Value.absent(),
    String? cleanupJson,
    Value<int?> recoveredAtUs = const Value.absent(),
    Value<String?> recoveryReason = const Value.absent(),
    int? summaryFormatVersion,
  }) => StoredRun(
    runId: runId ?? this.runId,
    operation: operation ?? this.operation,
    appVersion: appVersion ?? this.appVersion,
    profileId: profileId.present ? profileId.value : this.profileId,
    configurationJson: configurationJson ?? this.configurationJson,
    preparedAtUs: preparedAtUs ?? this.preparedAtUs,
    logicalEndedAtUs: logicalEndedAtUs.present
        ? logicalEndedAtUs.value
        : this.logicalEndedAtUs,
    recordState: recordState ?? this.recordState,
    resultJson: resultJson.present ? resultJson.value : this.resultJson,
    cleanupJson: cleanupJson ?? this.cleanupJson,
    recoveredAtUs: recoveredAtUs.present
        ? recoveredAtUs.value
        : this.recoveredAtUs,
    recoveryReason: recoveryReason.present
        ? recoveryReason.value
        : this.recoveryReason,
    summaryFormatVersion: summaryFormatVersion ?? this.summaryFormatVersion,
  );
  StoredRun copyWithCompanion(StoredRunsCompanion data) {
    return StoredRun(
      runId: data.runId.present ? data.runId.value : this.runId,
      operation: data.operation.present ? data.operation.value : this.operation,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      configurationJson: data.configurationJson.present
          ? data.configurationJson.value
          : this.configurationJson,
      preparedAtUs: data.preparedAtUs.present
          ? data.preparedAtUs.value
          : this.preparedAtUs,
      logicalEndedAtUs: data.logicalEndedAtUs.present
          ? data.logicalEndedAtUs.value
          : this.logicalEndedAtUs,
      recordState: data.recordState.present
          ? data.recordState.value
          : this.recordState,
      resultJson: data.resultJson.present
          ? data.resultJson.value
          : this.resultJson,
      cleanupJson: data.cleanupJson.present
          ? data.cleanupJson.value
          : this.cleanupJson,
      recoveredAtUs: data.recoveredAtUs.present
          ? data.recoveredAtUs.value
          : this.recoveredAtUs,
      recoveryReason: data.recoveryReason.present
          ? data.recoveryReason.value
          : this.recoveryReason,
      summaryFormatVersion: data.summaryFormatVersion.present
          ? data.summaryFormatVersion.value
          : this.summaryFormatVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredRun(')
          ..write('runId: $runId, ')
          ..write('operation: $operation, ')
          ..write('appVersion: $appVersion, ')
          ..write('profileId: $profileId, ')
          ..write('configurationJson: $configurationJson, ')
          ..write('preparedAtUs: $preparedAtUs, ')
          ..write('logicalEndedAtUs: $logicalEndedAtUs, ')
          ..write('recordState: $recordState, ')
          ..write('resultJson: $resultJson, ')
          ..write('cleanupJson: $cleanupJson, ')
          ..write('recoveredAtUs: $recoveredAtUs, ')
          ..write('recoveryReason: $recoveryReason, ')
          ..write('summaryFormatVersion: $summaryFormatVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    runId,
    operation,
    appVersion,
    profileId,
    configurationJson,
    preparedAtUs,
    logicalEndedAtUs,
    recordState,
    resultJson,
    cleanupJson,
    recoveredAtUs,
    recoveryReason,
    summaryFormatVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredRun &&
          other.runId == this.runId &&
          other.operation == this.operation &&
          other.appVersion == this.appVersion &&
          other.profileId == this.profileId &&
          other.configurationJson == this.configurationJson &&
          other.preparedAtUs == this.preparedAtUs &&
          other.logicalEndedAtUs == this.logicalEndedAtUs &&
          other.recordState == this.recordState &&
          other.resultJson == this.resultJson &&
          other.cleanupJson == this.cleanupJson &&
          other.recoveredAtUs == this.recoveredAtUs &&
          other.recoveryReason == this.recoveryReason &&
          other.summaryFormatVersion == this.summaryFormatVersion);
}

class StoredRunsCompanion extends UpdateCompanion<StoredRun> {
  final Value<String> runId;
  final Value<String> operation;
  final Value<String> appVersion;
  final Value<String?> profileId;
  final Value<String> configurationJson;
  final Value<int> preparedAtUs;
  final Value<int?> logicalEndedAtUs;
  final Value<String> recordState;
  final Value<String?> resultJson;
  final Value<String> cleanupJson;
  final Value<int?> recoveredAtUs;
  final Value<String?> recoveryReason;
  final Value<int> summaryFormatVersion;
  final Value<int> rowid;
  const StoredRunsCompanion({
    this.runId = const Value.absent(),
    this.operation = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.profileId = const Value.absent(),
    this.configurationJson = const Value.absent(),
    this.preparedAtUs = const Value.absent(),
    this.logicalEndedAtUs = const Value.absent(),
    this.recordState = const Value.absent(),
    this.resultJson = const Value.absent(),
    this.cleanupJson = const Value.absent(),
    this.recoveredAtUs = const Value.absent(),
    this.recoveryReason = const Value.absent(),
    this.summaryFormatVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredRunsCompanion.insert({
    required String runId,
    required String operation,
    required String appVersion,
    this.profileId = const Value.absent(),
    required String configurationJson,
    required int preparedAtUs,
    this.logicalEndedAtUs = const Value.absent(),
    required String recordState,
    this.resultJson = const Value.absent(),
    required String cleanupJson,
    this.recoveredAtUs = const Value.absent(),
    this.recoveryReason = const Value.absent(),
    required int summaryFormatVersion,
    this.rowid = const Value.absent(),
  }) : runId = Value(runId),
       operation = Value(operation),
       appVersion = Value(appVersion),
       configurationJson = Value(configurationJson),
       preparedAtUs = Value(preparedAtUs),
       recordState = Value(recordState),
       cleanupJson = Value(cleanupJson),
       summaryFormatVersion = Value(summaryFormatVersion);
  static Insertable<StoredRun> custom({
    Expression<String>? runId,
    Expression<String>? operation,
    Expression<String>? appVersion,
    Expression<String>? profileId,
    Expression<String>? configurationJson,
    Expression<int>? preparedAtUs,
    Expression<int>? logicalEndedAtUs,
    Expression<String>? recordState,
    Expression<String>? resultJson,
    Expression<String>? cleanupJson,
    Expression<int>? recoveredAtUs,
    Expression<String>? recoveryReason,
    Expression<int>? summaryFormatVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (runId != null) 'run_id': runId,
      if (operation != null) 'operation': operation,
      if (appVersion != null) 'app_version': appVersion,
      if (profileId != null) 'profile_id': profileId,
      if (configurationJson != null) 'configuration_json': configurationJson,
      if (preparedAtUs != null) 'prepared_at_us': preparedAtUs,
      if (logicalEndedAtUs != null) 'logical_ended_at_us': logicalEndedAtUs,
      if (recordState != null) 'record_state': recordState,
      if (resultJson != null) 'result_json': resultJson,
      if (cleanupJson != null) 'cleanup_json': cleanupJson,
      if (recoveredAtUs != null) 'recovered_at_us': recoveredAtUs,
      if (recoveryReason != null) 'recovery_reason': recoveryReason,
      if (summaryFormatVersion != null)
        'summary_format_version': summaryFormatVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredRunsCompanion copyWith({
    Value<String>? runId,
    Value<String>? operation,
    Value<String>? appVersion,
    Value<String?>? profileId,
    Value<String>? configurationJson,
    Value<int>? preparedAtUs,
    Value<int?>? logicalEndedAtUs,
    Value<String>? recordState,
    Value<String?>? resultJson,
    Value<String>? cleanupJson,
    Value<int?>? recoveredAtUs,
    Value<String?>? recoveryReason,
    Value<int>? summaryFormatVersion,
    Value<int>? rowid,
  }) {
    return StoredRunsCompanion(
      runId: runId ?? this.runId,
      operation: operation ?? this.operation,
      appVersion: appVersion ?? this.appVersion,
      profileId: profileId ?? this.profileId,
      configurationJson: configurationJson ?? this.configurationJson,
      preparedAtUs: preparedAtUs ?? this.preparedAtUs,
      logicalEndedAtUs: logicalEndedAtUs ?? this.logicalEndedAtUs,
      recordState: recordState ?? this.recordState,
      resultJson: resultJson ?? this.resultJson,
      cleanupJson: cleanupJson ?? this.cleanupJson,
      recoveredAtUs: recoveredAtUs ?? this.recoveredAtUs,
      recoveryReason: recoveryReason ?? this.recoveryReason,
      summaryFormatVersion: summaryFormatVersion ?? this.summaryFormatVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (configurationJson.present) {
      map['configuration_json'] = Variable<String>(configurationJson.value);
    }
    if (preparedAtUs.present) {
      map['prepared_at_us'] = Variable<int>(preparedAtUs.value);
    }
    if (logicalEndedAtUs.present) {
      map['logical_ended_at_us'] = Variable<int>(logicalEndedAtUs.value);
    }
    if (recordState.present) {
      map['record_state'] = Variable<String>(recordState.value);
    }
    if (resultJson.present) {
      map['result_json'] = Variable<String>(resultJson.value);
    }
    if (cleanupJson.present) {
      map['cleanup_json'] = Variable<String>(cleanupJson.value);
    }
    if (recoveredAtUs.present) {
      map['recovered_at_us'] = Variable<int>(recoveredAtUs.value);
    }
    if (recoveryReason.present) {
      map['recovery_reason'] = Variable<String>(recoveryReason.value);
    }
    if (summaryFormatVersion.present) {
      map['summary_format_version'] = Variable<int>(summaryFormatVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredRunsCompanion(')
          ..write('runId: $runId, ')
          ..write('operation: $operation, ')
          ..write('appVersion: $appVersion, ')
          ..write('profileId: $profileId, ')
          ..write('configurationJson: $configurationJson, ')
          ..write('preparedAtUs: $preparedAtUs, ')
          ..write('logicalEndedAtUs: $logicalEndedAtUs, ')
          ..write('recordState: $recordState, ')
          ..write('resultJson: $resultJson, ')
          ..write('cleanupJson: $cleanupJson, ')
          ..write('recoveredAtUs: $recoveredAtUs, ')
          ..write('recoveryReason: $recoveryReason, ')
          ..write('summaryFormatVersion: $summaryFormatVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CoreDatabase extends GeneratedDatabase {
  _$CoreDatabase(QueryExecutor e) : super(e);
  late final StoredDrafts storedDrafts = StoredDrafts(this);
  late final Index draftsUpdated = Index(
    'drafts_updated',
    'CREATE INDEX drafts_updated ON stored_drafts (updated_at_us DESC, id DESC)',
  );
  late final StoredProfiles storedProfiles = StoredProfiles(this);
  late final Index profilesUpdated = Index(
    'profiles_updated',
    'CREATE INDEX profiles_updated ON stored_profiles (updated_at_us DESC, id DESC)',
  );
  late final StoredSettings storedSettings = StoredSettings(this);
  late final StoredRuns storedRuns = StoredRuns(this);
  late final Index runsPrepared = Index(
    'runs_prepared',
    'CREATE INDEX runs_prepared ON stored_runs (prepared_at_us DESC, run_id DESC)',
  );
  late final Index runsOperation = Index(
    'runs_operation',
    'CREATE INDEX runs_operation ON stored_runs (operation, prepared_at_us DESC, run_id DESC)',
  );
  late final Index runsState = Index(
    'runs_state',
    'CREATE INDEX runs_state ON stored_runs (record_state, prepared_at_us DESC, run_id DESC)',
  );
  late final Index runsOperationState = Index(
    'runs_operation_state',
    'CREATE INDEX runs_operation_state ON stored_runs (operation, record_state, prepared_at_us DESC, run_id DESC)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    storedDrafts,
    draftsUpdated,
    storedProfiles,
    profilesUpdated,
    storedSettings,
    storedRuns,
    runsPrepared,
    runsOperation,
    runsState,
    runsOperationState,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'stored_profiles',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('stored_settings', kind: UpdateKind.update)],
    ),
  ]);
}
