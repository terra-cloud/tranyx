// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    show FieldValueFactoryPlatform;
import 'package:flutter_test/flutter_test.dart';

// Custom FieldValue Delegate to mock it in pure Dart
class CustomFieldValueDelegate {
  final String type;
  final dynamic value;

  CustomFieldValueDelegate(this.type, [this.value]);

  @override
  String toString() => 'FieldValue.$type($value)';
}

class CustomFieldValueFactory extends FieldValueFactoryPlatform {
  @override
  dynamic increment(num value) => CustomFieldValueDelegate('increment', value);

  @override
  dynamic serverTimestamp() => CustomFieldValueDelegate('serverTimestamp');
}

class FakeFirebaseFirestore extends Fake implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> db;

  FakeFirebaseFirestore([Map<String, Map<String, dynamic>>? initialDb])
    : db = initialDb ?? {} {
    FieldValueFactoryPlatform.instance = CustomFieldValueFactory();
  }

  final List<String> collectionQueries = [];

  void recordCollectionAccess(String path) {
    if (!collectionQueries.contains(path)) {
      collectionQueries.add(path);
    }
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    recordCollectionAccess(collectionPath);
    return FakeCollectionReference(this, collectionPath);
  }

  @override
  Query<Map<String, dynamic>> collectionGroup(String collectionPath) {
    recordCollectionAccess(collectionPath);
    return FakeQuery(this, collectionPath, isGroup: true);
  }

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final transaction = FakeTransaction(this);
    return await transactionHandler(transaction);
  }

  @override
  WriteBatch batch() {
    return FakeWriteBatch(this);
  }
}

class FakeCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String path;

  FakeCollectionReference(this.firestore, this.path);

  @override
  String get id => path.split('/').last;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final docId = path ?? 'doc_${DateTime.now().microsecondsSinceEpoch}';
    final fullPath = '${this.path}/$docId';
    return FakeDocumentReference(firestore, fullPath);
  }

  @override
  Future<DocumentReference<Map<String, dynamic>>> add(
    Map<String, dynamic> data,
  ) async {
    final docId = 'doc_${DateTime.now().microsecondsSinceEpoch}';
    final fullPath = '$path/$docId';
    firestore.db[fullPath] = Map<String, dynamic>.from(data);
    return FakeDocumentReference(firestore, fullPath);
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();

    void emit() {
      final docSnaps = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      firestore.db.forEach((key, val) {
        if (key.startsWith('$path/') &&
            key.substring(path.length + 1).split('/').length == 1) {
          docSnaps.add(FakeQueryDocumentSnapshot(firestore, key, val));
        }
      });
      controller.add(FakeQuerySnapshot(docSnaps));
    }

    emit();
    return controller.stream;
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final docSnaps = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    firestore.db.forEach((key, val) {
      if (key.startsWith('$path/') &&
          key.substring(path.length + 1).split('/').length == 1) {
        docSnaps.add(FakeQueryDocumentSnapshot(firestore, key, val));
      }
    });
    return FakeQuerySnapshot(docSnaps);
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    return FakeQuery(firestore, path).where(
      field,
      isEqualTo: isEqualTo,
      isNotEqualTo: isNotEqualTo,
      isLessThan: isLessThan,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
      isGreaterThan: isGreaterThan,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      arrayContains: arrayContains,
      arrayContainsAny: arrayContainsAny,
      whereIn: whereIn,
      whereNotIn: whereNotIn,
      isNull: isNull,
    );
  }

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    return FakeQuery(firestore, path).orderBy(field, descending: descending);
  }
}

class FakeDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String path;

  FakeDocumentReference(this.firestore, this.path);

  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return FakeCollectionReference(firestore, '$path/$collectionPath');
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    final data = firestore.db[path];
    return FakeDocumentSnapshot(firestore, path, data);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (options != null && options.merge == true) {
      final existing = firestore.db[path] ?? {};
      firestore.db[path] = _resolveFieldValues(existing, data);
    } else {
      firestore.db[path] = _resolveFieldValues({}, data);
    }
  }

  @override
  Future<void> update(Map<Object?, Object?> data) async {
    final existing = firestore.db[path];
    if (existing == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'Document not found for update: $path',
      );
    }
    final mapData = Map<String, dynamic>.from(data);
    firestore.db[path] = _resolveFieldValues(existing, mapData);
  }

  @override
  Future<void> delete() async {
    firestore.db.remove(path);
  }
}

class FakeDocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String path;
  final Map<String, dynamic>? _data;

  FakeDocumentSnapshot(this.firestore, this.path, this._data);

  @override
  String get id => path.split('/').last;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic operator [](Object field) => _data?[field];

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      FakeDocumentReference(firestore, path);
}

class FakeQueryDocumentSnapshot extends FakeDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  FakeQueryDocumentSnapshot(
    FakeFirebaseFirestore firestore,
    String path,
    Map<String, dynamic> data,
  ) : super(firestore, path, data);

  @override
  Map<String, dynamic> data() => super.data()!;
}

class FakeQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  FakeQuerySnapshot(this.docs);
}

class FakeQuery extends Fake implements Query<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String path;
  final bool isGroup;
  final List<bool Function(Map<String, dynamic>)> filters = [];

  FakeQuery(this.firestore, this.path, {this.isGroup = false});

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    filters.add((data) {
      final val = data[field];
      if (isEqualTo != null && val != isEqualTo) return false;
      if (isNotEqualTo != null && val == isNotEqualTo) return false;
      if (arrayContains != null) {
        if (val is! List || !val.contains(arrayContains)) return false;
      }
      return true;
    });
    return this;
  }

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    return this;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();

    void emit() async {
      final res = await get();
      controller.add(res);
    }

    emit();
    return controller.stream;
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final docSnaps = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    firestore.db.forEach((key, val) {
      if (isGroup) {
        final parts = key.split('/');
        if (parts.length >= 2 && parts[parts.length - 2] == path) {
          var match = true;
          for (final filter in filters) {
            if (!filter(val)) {
              match = false;
              break;
            }
          }
          if (match) {
            docSnaps.add(FakeQueryDocumentSnapshot(firestore, key, val));
          }
        }
      } else {
        if (key.startsWith('$path/') &&
            key.substring(path.length + 1).split('/').length == 1) {
          var match = true;
          for (final filter in filters) {
            if (!filter(val)) {
              match = false;
              break;
            }
          }
          if (match) {
            docSnaps.add(FakeQueryDocumentSnapshot(firestore, key, val));
          }
        }
      }
    });
    return FakeQuerySnapshot(docSnaps);
  }
}

class FakeTransaction extends Fake implements Transaction {
  final FakeFirebaseFirestore firestore;

  FakeTransaction(this.firestore);

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    final ref = documentReference as FakeDocumentReference;
    final data = firestore.db[ref.path];
    return FakeDocumentSnapshot(firestore, ref.path, data)
        as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    final ref = documentReference as FakeDocumentReference;
    final mapData = data as Map<String, dynamic>;
    if (options != null && options.merge == true) {
      final existing = firestore.db[ref.path] ?? {};
      firestore.db[ref.path] = _resolveFieldValues(existing, mapData);
    } else {
      firestore.db[ref.path] = _resolveFieldValues({}, mapData);
    }
    return this;
  }

  @override
  Transaction update(
    DocumentReference documentReference,
    Map<Object?, Object?> data,
  ) {
    final ref = documentReference as FakeDocumentReference;
    final mapData = Map<String, dynamic>.from(data);
    final existing = firestore.db[ref.path] ?? {};
    firestore.db[ref.path] = _resolveFieldValues(existing, mapData);
    return this;
  }

  @override
  Transaction delete(DocumentReference documentReference) {
    final ref = documentReference as FakeDocumentReference;
    firestore.db.remove(ref.path);
    return this;
  }
}

class FakeWriteBatch extends Fake implements WriteBatch {
  final FakeFirebaseFirestore firestore;
  final List<void Function()> operations = [];

  FakeWriteBatch(this.firestore);

  @override
  void update(DocumentReference documentReference, Map<Object?, Object?> data) {
    final ref = documentReference as FakeDocumentReference;
    final mapData = Map<String, dynamic>.from(data);
    operations.add(() {
      final existing = firestore.db[ref.path] ?? {};
      firestore.db[ref.path] = _resolveFieldValues(existing, mapData);
    });
  }

  @override
  Future<void> commit() async {
    for (final op in operations) {
      op();
    }
  }
}

Map<String, dynamic> _resolveFieldValues(
  Map<String, dynamic> existing,
  Map<String, dynamic> update,
) {
  final result = Map<String, dynamic>.from(existing);
  update.forEach((key, val) {
    if (val is FieldValue) {
      final valStr = val.toString();
      if (valStr.contains('increment')) {
        final numPart =
            RegExp(r'value:\s*([-\d\.]+)').firstMatch(valStr)?.group(1) ??
            RegExp(r'increment\(([-\d\.]+)\)').firstMatch(valStr)?.group(1) ??
            '1';
        final incVal = num.tryParse(numPart) ?? 1;
        final currentVal = (result[key] as num?) ?? 0;
        result[key] = currentVal + incVal;
      } else if (valStr.contains('serverTimestamp')) {
        result[key] = DateTime.now().millisecondsSinceEpoch;
      }
    } else {
      result[key] = val;
    }
  });
  return result;
}
