import 'package:test/test.dart';
import '../src/ObservableList.dart';
import '../src/Model.dart';

class TestDoc extends Model {
  TestDoc.fromJson() : super.fromJson({});
}

void main() {
  group("ObservableList", () {
    group('ObservableList: Basic scenarios', () {
      late ObservableList<TestDoc> list;

      setUp(() {
        list = ObservableList<TestDoc>();
      });

      test('should add an item and notify observers', () async {
        final testDoc = TestDoc.fromJson();
        bool callbackCalled = false;

        list.observe((events) {
          expect(events.length, 1);
          expect(events.first.type, EventType.add);
          callbackCalled = true;
        });

        list.add(testDoc);
        await Future.delayed(Duration(milliseconds: 10));
        expect(list.docs.length, 1);
        expect(callbackCalled, isTrue);
      });

      test('should add multiple items and notify observers', () async {
        final docs = List.generate(3, (i) => TestDoc.fromJson());
        bool callbackCalled = false;

        list.observe((events) {
          expect(events.length, 3);
          for (int i = 0; i < 3; i++) {
            expect(events[i].type, EventType.add);
          }
          callbackCalled = true;
        });

        list.addAll(docs);
        expect(list.docs.length, 3);
        await Future.delayed(Duration(milliseconds: 10));
        expect(callbackCalled, isTrue);
      });

      test('should remove an item and notify observers', () async {
        final testDoc = TestDoc.fromJson();
        list.add(testDoc);

        bool callbackCalled = false;
        list.observe((events) {
          expect(events.length, 1);
          expect(events.first.type, EventType.remove);
          callbackCalled = true;
        });

        list.remove(testDoc);
        expect(list.docs.length, 0);
        await Future.delayed(Duration(milliseconds: 10));
        expect(callbackCalled, isTrue);
      });

      test('should modify an item and notify observers', () async {
        final testDoc = TestDoc.fromJson();
        list.add(testDoc);

        bool callbackCalled = false;
        list.observe((events) {
          expect(events.length, 1);
          expect(events.first.type, EventType.modify);
          callbackCalled = true;
        });

        final modifiedDoc = list.docs.first..archived = true;
        list.modify(modifiedDoc);
        await Future.delayed(Duration(milliseconds: 10));
        expect(callbackCalled, isTrue);
      });

      test('should clear the list and notify observers', () async {
        final testDoc = TestDoc.fromJson();
        list.add(testDoc);

        bool callbackCalled = false;
        list.observe((events) {
          expect(events.length, 1);
          expect(events.first.type, EventType.remove);
          callbackCalled = true;
        });

        list.clear();
        expect(list.docs.length, 0);
        await Future.delayed(Duration(milliseconds: 1));
        expect(callbackCalled, isTrue);
      });

      test('should handle silent operations', () {
        final testDoc = TestDoc.fromJson();
        bool callbackCalled = false;

        list.observe((events) {
          callbackCalled = true;
        });

        list.silently(() {
          list.add(testDoc);
        });

        expect(list.docs.length, 1);
        expect(callbackCalled, isFalse);
      });

      test('should add an observer and unregister it', () {
        final testDoc = TestDoc.fromJson();
        bool callbackCalled = false;

        final observerId = list.observe((events) {
          callbackCalled = true;
        });

        list.unObserve(observerId);
        list.add(testDoc);

        expect(callbackCalled, isFalse);
      });

      test('should handle errors in observers', () async {
        final testDoc = TestDoc.fromJson();

        list.observe((events) {
          throw Exception('Test error');
        });

        list.add(testDoc);
        await Future.delayed(Duration(milliseconds: 10));
        expect(list.errors.length, 1);
        expect(list.errors.first.message, 'Exception: Test error');
      });

      test('should dispose and stop all observations', () async {
        final testDoc = TestDoc.fromJson();
        bool callbackCalled = false;

        list.observe((events) {
          callbackCalled = true;
        });

        list.dispose();
        list.add(testDoc);
        await Future.delayed(Duration(milliseconds: 10));
        expect(callbackCalled, isFalse);
      });

      test('should return first item matching the test', () {
        final doc1 = TestDoc.fromJson();
        final doc2 = TestDoc.fromJson();
        list.addAll([doc1, doc2]);

        final result = list.firstWhere((doc) => doc.id == doc1.id);
        expect(result, doc1);
      });

      test('should return first index matching the test', () {
        final doc1 = TestDoc.fromJson();
        final doc2 = TestDoc.fromJson();
        list.addAll([doc1, doc2]);

        final index = list.indexWhere((doc) => doc.id == doc2.id);
        expect(index, 1);
      });

      test('should return index of item with given id', () {
        final doc1 = TestDoc.fromJson();
        final doc2 = TestDoc.fromJson();
        list.addAll([doc1, doc2]);

        final index = list.indexOfId(doc2.id);
        expect(index, 1);
      });

      test('should handle adding duplicate items', () {
        final doc = TestDoc.fromJson();
        list.add(doc);
        list.add(doc);
        expect(list.docs.length, 2);
        expect(list.docs[0], list.docs[1]);
      });

      test('should handle removing non-existent item', () {
        final doc = TestDoc.fromJson();
        list.remove(doc);
        expect(list.docs.length, 0);
      });

      test('should handle modifying non-existent item', () {
        final doc = TestDoc.fromJson();
        list.modify(doc);
        expect(list.docs.length, 0);
      });

      test('should handle multiple observers', () async {
        final doc = TestDoc.fromJson();
        int observer1CallCount = 0;
        int observer2CallCount = 0;

        list.observe((_) => observer1CallCount++);
        list.observe((_) => observer2CallCount++);

        list.add(doc);
        await Future.delayed(Duration(milliseconds: 10));
        expect(observer1CallCount, 1);
        expect(observer2CallCount, 1);
      });

      test('should handle rapid add and remove operations', () async {
        final docs = List.generate(1000, (_) => TestDoc.fromJson());
        int addCount = 0;
        int removeCount = 0;

        list.observe((events) {
          addCount += events.where((e) => e.type == EventType.add).length;
          removeCount += events.where((e) => e.type == EventType.remove).length;
        });

        for (var doc in docs) {
          list.add(doc);
          list.remove(doc);
        }

        await Future.delayed(Duration(milliseconds: 100));
        expect(addCount, 1000);
        expect(removeCount, 1000);
        expect(list.docs.isEmpty, true);
      });

      test('should handle concurrent modifications', () async {
        final docs = List.generate(100, (_) => TestDoc.fromJson());
        list.addAll(docs);

        Future.wait([
          Future(() => list.modify(docs[0]..archived = true)),
          Future(() => list.remove(docs[1])),
          Future(() => list.add(TestDoc.fromJson())),
        ]);

        await Future.delayed(Duration(milliseconds: 50));
        expect(list.docs.length, 100);
        expect(list.docs[0].archived, true);
      });

      test('should handle large number of observers', () async {
        final doc = TestDoc.fromJson();
        final observers = List.generate(1000, (_) => 0);

        for (int i = 0; i < 1000; i++) {
          list.observe((_) => observers[i]++);
        }

        list.add(doc);
        await Future.delayed(Duration(milliseconds: 50));
        expect(observers.every((count) => count == 1), true);
      });

      test('should maintain correct indices after multiple operations', () async {
        final docs = List.generate(5, (_) => TestDoc.fromJson());
        list.addAll(docs);

        list.remove(docs[2]);
        list.add(TestDoc.fromJson());
        list.modify(docs[0]..archived = true);

        await Future.delayed(Duration(milliseconds: 10));
        expect(list.docs.length, 5);
        expect(list.indexOfId(docs[0].id), 0);
        expect(list.indexOfId(docs[1].id), 1);
        expect(list.indexOfId(docs[3].id), 2);
        expect(list.indexOfId(docs[4].id), 3);
        expect(list.docs[0].archived, true);
      });

      test('should handle errors in silently block', () {
        list.silently(() {
          throw Exception('Test error in silently block');
        });

        expect(list.errors.length, 1);
        expect(list.errors.first.message, 'Exception: Test error in silently block');
      });

      test('should not notify after dispose even if add is called', () async {
        bool callbackCalled = false;
        list.observe((_) => callbackCalled = true);

        list.dispose();
        list.add(TestDoc.fromJson());

        await Future.delayed(Duration(milliseconds: 10));
        expect(callbackCalled, false);
      });
    });

    group('ObservableList: Complex Scenarios', () {
      late ObservableList<TestDoc> list;

      setUp(() {
        list = ObservableList<TestDoc>();
      });

      test('should handle interleaved add, remove, and modify operations', () async {
        final docs = List.generate(10, (_) => TestDoc.fromJson());
        List<OEvent> capturedEvents = [];

        list.observe((events) => capturedEvents.addAll(events));

        // Interleave operations
        list.addAll(docs.sublist(0, 5));
        list.remove(docs[2]);
        list.add(docs[5]);
        list.modify(docs[0]..archived = true);
        list.remove(docs[1]);
        list.addAll(docs.sublist(6, 8));
        list.modify(docs[7]..archived = true);

        await Future.delayed(Duration(milliseconds: 50));

        expect(list.docs.length, 6);
        expect(capturedEvents.length, 12);
        expect(list.docs[0].archived, true);
        expect(list.docs[5].archived, true);
        expect(capturedEvents.where((e) => e.type == EventType.add).length, 8);
        expect(capturedEvents.where((e) => e.type == EventType.remove).length, 2);
        expect(capturedEvents.where((e) => e.type == EventType.modify).length, 2);
      });

      test('should handle rapid add and remove with multiple observers', () async {
        final docs = List.generate(1000, (_) => TestDoc.fromJson());
        List<int> observerCounts = List.generate(5, (_) => 0);

        for (int i = 0; i < 5; i++) {
          list.observe((events) => observerCounts[i] += events.length);
        }

        await Future(() {
          for (var doc in docs) {
            list.add(doc);
            list.remove(doc);
          }
        });

        await Future.delayed(Duration(milliseconds: 100));
        expect(list.docs.isEmpty, true);
        expect(observerCounts.every((count) => count == 2000), true);
      });

      test('should handle concurrent modifications with error', () async {
        final docs = List.generate(100, (_) => TestDoc.fromJson());
        list.addAll(docs);

        list.observe((events) {
          if (events.any((e) => e.type == EventType.modify)) {
            throw Exception('Simulated error');
          }
        });

        await Future.wait([
          Future(() => list.modify(docs[0]..archived = true)),
          Future(() => list.remove(docs[1])),
          Future(() => list.add(TestDoc.fromJson())),
        ]);

        await Future.delayed(Duration(milliseconds: 50));
        expect(list.docs.length, 100);
        expect(list.docs[0].archived, true);
        expect(list.errors.length, 1);
        expect(list.errors.first.message, 'Exception: Simulated error');
      });

      test('should handle nested silent operations', () async {
        final doc1 = TestDoc.fromJson();
        final doc2 = TestDoc.fromJson();
        int callCount = 0;

        list.observe((_) => callCount++);

        list.silently(() {
          list.add(doc1);
          list.silently(() {
            list.add(doc2);
          });
          list.modify(doc1..archived = true);
        });

        list.add(TestDoc.fromJson());

        await Future.delayed(Duration(milliseconds: 50));
        expect(list.docs.length, 3);
        expect(list.docs[0].archived, true);
        expect(callCount, 1);
      });

      test('should handle reentrant modifications', () async {
        final doc = TestDoc.fromJson();
        int callCount = 0;

        list.observe((events) {
          callCount++;
          if (events.first.type == EventType.add) {
            list.modify(doc..archived = true);
          }
        });

        list.add(doc);

        await Future.delayed(Duration(milliseconds: 50));
        expect(list.docs.length, 1);
        expect(list.docs[0].archived, true);
        expect(callCount, 2);
      });

      test('should handle observer throwing error and continue notifying others', () async {
        final doc = TestDoc.fromJson();
        int goodObserverCount = 0;

        list.observe((_) => throw Exception('Simulated error'));
        list.observe((_) => goodObserverCount++);

        list.add(doc);

        await Future.delayed(Duration(milliseconds: 50));
        expect(list.docs.length, 1);
        expect(goodObserverCount, 1);
        expect(list.errors.length, 1);
        expect(list.errors.first.message, 'Exception: Simulated error');
      });

      test('should handle adding and removing same item multiple times', () async {
        final doc = TestDoc.fromJson();
        List<OEvent> capturedEvents = [];

        list.observe((events) => capturedEvents.addAll(events));

        for (int i = 0; i < 5; i++) {
          list.add(doc);
          list.remove(doc);
        }

        await Future.delayed(Duration(milliseconds: 50));
        expect(list.docs.isEmpty, true);
        expect(capturedEvents.length, 10);
        expect(capturedEvents.where((e) => e.type == EventType.add).length, 5);
        expect(capturedEvents.where((e) => e.type == EventType.remove).length, 5);
      });

      test('should handle modifying item during iteration', () {
        final docs = List.generate(10, (_) => TestDoc.fromJson());
        list.addAll(docs);

        for (var doc in list.docs) {
          list.modify(doc..archived = true);
        }

        expect(list.docs.every((doc) => doc.archived ?? false), true);
      });
    });
  });
}
