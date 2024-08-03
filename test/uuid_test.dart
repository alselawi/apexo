import 'package:test/test.dart';
import "../src/uuid.dart" as UUID;

void main() {
  group('uuid', () {
    test('generates a valid UUID v4 string', () {
      final uuid = UUID.uuid();
      expect(
          uuid,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('generates unique UUIDs', () {
      final uuids = List.generate(1000, (_) => UUID.uuid());
      expect(uuids.toSet().length, equals(1000));
    });

    test('generates UUIDs with correct version (4)', () {
      final uuid = UUID.uuid();
      expect(uuid[14], equals('4'));
    });

    test('generates UUIDs with correct variant (1)', () {
      final uuid = UUID.uuid();
      expect(int.parse(uuid[19], radix: 16) & 0xC, equals(0x8));
    });

    test('generates UUIDs with correct length', () {
      final uuid = UUID.uuid();
      expect(uuid.length, equals(36));
    });

    test('generates UUIDs with correct number of hyphens', () {
      final uuid = UUID.uuid();
      expect(uuid.split('-').length, equals(5));
    });

    test('generates UUIDs with correct segment lengths', () {
      final uuid = UUID.uuid();
      final segments = uuid.split('-');
      expect(segments[0].length, equals(8));
      expect(segments[1].length, equals(4));
      expect(segments[2].length, equals(4));
      expect(segments[3].length, equals(4));
      expect(segments[4].length, equals(12));
    });
  });
}
