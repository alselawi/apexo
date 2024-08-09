import 'package:test/test.dart';
import 'package:hive/hive.dart';
import 'dart:io';
import "../src/SaveLocal.dart";

// Import your SaveLocal class here
// import 'path_to_your_file.dart';

void main() async {
  late SaveLocal saveLocal;

  setUpAll(() async {
    // Initialize Hive for testing
    final tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);
  });

  setUp(() {
    saveLocal = SaveLocal('testBox');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('testBox:main');
    await Hive.deleteBoxFromDisk('testBox:meta');
  });

  tearDownAll(() async {
    await Hive.close();
  });

  group('SaveLocal', () {
    test('put and get single item', () async {
      await saveLocal.put({'key1': 'value1'});
      expect(await saveLocal.get('key1'), equals('value1'));
    });

    test('put and get multiple items', () async {
      await saveLocal.put({'key1': 'value1', 'key2': 'value2'});
      expect(await saveLocal.get('key1'), equals('value1'));
      expect(await saveLocal.get('key2'), equals('value2'));
    });

    test('get non-existent key returns empty string', () async {
      expect(await saveLocal.get('nonExistentKey'), equals(''));
    });

    test('getAll returns all values', () async {
      await saveLocal.put({'key1': 'value1', 'key2': 'value2'});
      final allValues = await saveLocal.getAll();
      expect(allValues, containsAll(['value1', 'value2']));
      expect(allValues.length, equals(2));
    });

    test('getVersion and putVersion', () async {
      await saveLocal.putVersion(5);
      expect(await saveLocal.getVersion(), equals(5));
    });

    test('getVersion returns 0 when not set', () async {
      expect(await saveLocal.getVersion(), equals(0));
    });

    test('getDeferred and putDeferred', () async {
      final deferredData = {'key1': 1, 'key2': 2};
      await saveLocal.putDeferred(deferredData);
      expect(await saveLocal.getDeferred(), equals(deferredData));
    });

    test('getDeferred returns empty map when not set', () async {
      expect(await saveLocal.getDeferred(), equals({}));
    });

    test('dump and restore', () async {
      await saveLocal.put({'mainKey': 'mainValue'});
      await saveLocal.putVersion(3);
      await saveLocal.putDeferred({'deferredKey': 1});

      final dump = await saveLocal.dump();

      // Clear the boxes
      await saveLocal.put({});
      await saveLocal.putVersion(0);
      await saveLocal.putDeferred({});

      // Restore from dump
      await saveLocal.restore(dump);

      expect(await saveLocal.get('mainKey'), equals('mainValue'));
      expect(await saveLocal.getVersion(), equals(3));
      expect(await saveLocal.getDeferred(), equals({'deferredKey': 1}));
    });

    test('put with empty map', () async {
      await saveLocal.put({});
      expect(await saveLocal.getAll(), isEmpty);
    });

    test('put overwrites existing values', () async {
      await saveLocal.put({'key': 'value1'});
      await saveLocal.put({'key': 'value2'});
      expect(await saveLocal.get('key'), equals('value2'));
    });

    test('getAll on empty box', () async {
      expect(await saveLocal.getAll(), isEmpty);
    });

    test('putVersion with negative value', () async {
      await saveLocal.putVersion(-1);
      expect(await saveLocal.getVersion(), equals(-1));
    });

    test('putDeferred with empty map', () async {
      await saveLocal.putDeferred({});
      expect(await saveLocal.getDeferred(), equals({}));
    });

    test('dump on empty boxes', () async {
      final dump = await saveLocal.dump();
      expect(dump.main, isEmpty);
      expect(dump.meta, isEmpty);
    });

    test('restore with empty dump', () async {
      await saveLocal.put({'key': 'value'});
      await saveLocal.putVersion(1);

      final emptyDump = Dump({}, {});
      await saveLocal.restore(emptyDump);

      expect(await saveLocal.getAll(), isEmpty);
      expect(await saveLocal.getVersion(), equals(0));
      expect(await saveLocal.getDeferred(), equals({}));
    });

    test('large data handling', () async {
      final Map<String, String> largeMap = Map.fromIterable(
        List.generate(1000, (i) => 'key$i'),
        value: (k) => List.generate(1000, (i) => 'a').join(),
      );

      await saveLocal.put(largeMap);
      expect(await saveLocal.get('key500'), equals(largeMap['key500']));
    });

    test('concurrent operations', () async {
      final futures = List.generate(100, (i) => saveLocal.put({'key$i': 'value$i'}));
      await Future.wait(futures);

      final allValues = await saveLocal.getAll();
      expect(allValues.length, equals(100));
    });

    test('error handling - invalid JSON for deferred', () async {
      final metaBox = await Hive.openBox<String>('testBox:meta');
      await metaBox.put("meta:deferred", '{invalid json}');

      expect(() => saveLocal.getDeferred(), throwsA(isA<StorageException>()));
    });

    test('version overflow', () async {
      await saveLocal.putVersion(9007199254740991); // Max safe integer in Dart
      expect(await saveLocal.getVersion(), equals(9007199254740991));

      // This should wrap around or throw an exception, depending on your implementation
      await saveLocal.putVersion(9007199254740991 + 1);
    });
  });
}
