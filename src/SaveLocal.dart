import 'dart:convert';
import 'dart:async';
import 'package:hive/hive.dart';

// Constants for metadata keys
const String _versionKey = 'meta:version';
const String _deferredKey = 'meta:deferred';

// Dump class for storing snapshots of data
class Dump {
  final Map<String, String> main;
  final Map<String, String> meta;
  Dump(this.main, this.meta);
}

// SaveLocal class for managing local storage operations
class SaveLocal {
  final String name;
  late final Future<Box<String>> _mainBox;
  late final Future<Box<String>> _metaBox;

  SaveLocal(this.name) {
    _mainBox = Hive.openBox<String>("$name:main");
    _metaBox = Hive.openBox<String>("$name:meta");
  }

  // Put entries into the main box
  Future<void> put(Map<String, String> entries) async {
    try {
      final box = await _mainBox;
      await box.putAll(entries);
    } catch (e, s) {
      throw StorageException('Failed to put entries: $e', s);
    }
  }

  // Get a value from the main box
  Future<String> get(String key) async {
    try {
      final box = await _mainBox;
      return box.get(key) ?? "";
    } catch (e, s) {
      throw StorageException('Failed to get value for key $key: $e', s);
    }
  }

  // Get all values from the main box
  Future<Iterable<String>> getAll() async {
    try {
      final box = await _mainBox;
      return box.values;
    } catch (e, s) {
      throw StorageException('Failed to get all values: $e', s);
    }
  }

  // Get version from meta box
  Future<int> getVersion() async {
    try {
      final Box box = await _metaBox;
      return int.parse(box.get(_versionKey) ?? "0");
    } catch (e, s) {
      throw StorageException('Failed to get version: $e', s);
    }
  }

  // Put version into meta box
  Future<void> putVersion(int versionValue) async {
    try {
      final Box box = await _metaBox;
      await box.put(_versionKey, versionValue.toString());
    } catch (e, s) {
      throw StorageException('Failed to put version: $e', s);
    }
  }

  // Get deferred data from meta box
  Future<Map<String, int>> getDeferred() async {
    try {
      final Box box = await _metaBox;
      final jsonString = box.get(_deferredKey) ?? "{}";
      return Map<String, int>.from(jsonDecode(jsonString));
    } catch (e, s) {
      throw StorageException('Failed to get deferred data: $e', s);
    }
  }

  // Put deferred data into meta box
  Future<void> putDeferred(Map<String, int> deferred) async {
    try {
      final Box box = await _metaBox;
      await box.put(_deferredKey, jsonEncode(deferred));
    } catch (e, s) {
      throw StorageException('Failed to put deferred data: $e', s);
    }
  }

  // Create a dump of both boxes
  Future<Dump> dump() async {
    try {
      final mainBox = await _mainBox;
      final metaBox = await _metaBox;
      return Dump(
        Map<String, String>.from(mainBox.toMap()),
        Map<String, String>.from(metaBox.toMap()),
      );
    } catch (e, s) {
      throw StorageException('Failed to create dump: $e', s);
    }
  }

  // Restore data from a dump
  Future<void> restore(Dump dump) async {
    try {
      final mainBox = await _mainBox;
      final metaBox = await _metaBox;
      // Clear existing data
      await clear();
      // put new data
      await mainBox.putAll(dump.main);
      await metaBox.putAll(dump.meta);
    } catch (e, s) {
      throw StorageException('Failed to restore from dump: $e', s);
    }
  }

  Future<void> clear() async {
    try {
      final mainBox = await _mainBox;
      final metaBox = await _metaBox;
      await mainBox.clear();
      await metaBox.clear();
    } catch (e, s) {
      throw StorageException('Failed to clear storage: $e', s);
    }
  }
}

// Custom exception for storage operations
class StorageException implements Exception {
  final String message;
  final StackTrace stackTrace;
  StorageException(this.message, this.stackTrace);
  @override
  String toString() => 'StorageException: $message';
}
