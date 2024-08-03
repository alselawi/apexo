import 'package:test/test.dart';
import "../src/hash.dart";

void main() {
  group('fastHash', () {
    test('returns consistent hash for same input', () {
      String input = 'test string';
      expect(fastHash(input), equals(fastHash(input)));
    });

    test('returns different hash for different inputs', () {
      String input1 = 'test string 1';
      String input2 = 'test string 2';
      expect(fastHash(input1), isNot(equals(fastHash(input2))));
    });

    test('handles empty string', () {
      expect(fastHash(''), isNotNull);
    });

    test('handles single character string', () {
      expect(fastHash('a'), isNotNull);
    });

    test('handles string with exactly 4 characters', () {
      expect(fastHash('abcd'), isNotNull);
    });

    test('handles string with length not divisible by 4', () {
      expect(fastHash('abcde'), isNotNull);
    });

    test('handles long string', () {
      String longString = 'a' * 1000;
      expect(fastHash(longString), isNotNull);
    });

    test('handles string with non-ASCII characters', () {
      expect(fastHash('こんにちは'), isNotNull);
    });
  });
}
