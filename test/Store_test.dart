import 'dart:io';
import 'package:hive/hive.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import '../src/Model.dart';
import '../src/SaveLocal.dart';
import '../src/SaveRemote.dart';
import '../src/Store.dart';

class Person extends Model {
  String name = 'alex';
  int age = 100;

  Person.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    name = json["name"] ?? name;
    age = json["age"] ?? age;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Person.fromJson({});
    if (name != d.name) json['name'] = name;
    if (age != d.age) json['age'] = age;
    return json;
  }

  get ageInDays => age * 365;
}

void main() {
  String name = "test";
  late Store<Person> store;
  late SaveLocal local;
  late SaveRemote remote;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);
  });

  setUp(() async {
    Uri server = Uri.parse("http://127.0.0.1:8787/staff");
    try {
      await http.get(server);
    } catch (e) {
      throw Exception("Apexo-database is not running");
    }

    await http.delete(server, headers: {
      'Authorization': 'Bearer null',
    });

    local = SaveLocal(name);
    remote = SaveRemote(baseUrl: "http://127.0.0.1:8787", token: "nill", table: "staff");

    await local.clear();
    await remote.clear();

    store = Store<Person>(local: local, remote: remote, modeling: Person.fromJson);
  });

  group("Store: ", () {
    group("basic functionality", () {
      test("store is loaded and modeled", () async {
        Box b = await Hive.openBox<String>("$name:main");
        await b.put("id0", '{"id":"some-id"}');

        Store<Person> store = Store<Person>(
            local: SaveLocal(name),
            remote: SaveRemote(baseUrl: "http://127.0.0.1:8787", token: "nill", table: "staff"),
            modeling: Person.fromJson);

        expect(store.docs.length, equals(0));
        await store.loaded;
        expect(store.docs.length, equals(1));
        expect(store.docs[0].name, equals(Person.fromJson({}).name));
        expect(store.docs[0].age, equals(Person.fromJson({}).age));
      });

      test("add methods correctly adds documents to the store", () async {
        store.add(Person.fromJson({}));
        expect(store.docs.length, equals(1));
        expect(store.docs[0].name, equals(Person.fromJson({}).name));
        expect(store.docs[0].age, equals(Person.fromJson({}).age));
      });
      test("get method grabs document by its id", () async {
        store.add(Person.fromJson({}));
        expect(store.get(store.docs[0].id).name, equals(Person.fromJson({}).name));
        expect(store.get(store.docs[0].id).age, equals(Person.fromJson({}).age));
      });
      test("getIndex method grabs document index by its id", () async {
        store.add(Person.fromJson({}));
        expect(store.getIndex(store.docs[0].id), equals(0));
      });
      test("archive method archives a document", () async {
        store.add(Person.fromJson({}));
        store.archive(store.docs[0].id);
        expect(store.docs[0].archived, isTrue);
      });
      test("unarchive method un-archives a document", () async {
        store.add(Person.fromJson({}));
        store.archive(store.docs[0].id);
        store.unarchive(store.docs[0].id);
        expect(store.docs[0].archived, isFalse);
      });
      test("delete method is an alias of archive", () async {
        store.add(Person.fromJson({}));
        store.delete(store.docs[0].id);
        expect(store.docs[0].archived, isTrue);
      });

      test("update method updates a document", () async {
        int called = 0;
        store.observableObject.observe((l) => called++);
        store.add(Person.fromJson({}));
        store.modify(store.docs[0]..age = 18);
        expect(store.docs[0].age, equals(18));
        await Future.delayed(Duration(milliseconds: 500));
        expect(called, equals(2));
      });

      test("reload method reloads the hive store correctly", () async {
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 500));
        expect(store.docs.length, equals(1));
        Box b = await Hive.openBox<String>("$name:main");
        await b.put("id0", '{"id":"some-id"}');
        await store.reload();
        expect(store.docs.length, equals(2));
      });
      test("reload method doesn't inform observers", () async {
        int called = 0;
        store.observableObject.observe((l) => called++);
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 500));
        expect(store.docs.length, equals(1));
        Box b = await Hive.openBox<String>("$name:main");
        await b.put("id0", '{"id":"some-id"}');
        await store.reload();
        expect(store.docs.length, equals(2));
        expect(called, equals(1));
      });
      test("debounceMS is considered in changes processing", () async {
        Store<Person> store2 = Store(local: local, remote: remote, modeling: Person.fromJson, debounceMS: 1000);
        await store.loaded;
        store2.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 50));
        expect((await local.getAll()).length, equals(0));
        await Future.delayed(Duration(milliseconds: 100));
        expect((await local.getAll()).length, equals(0));
        await Future.delayed(Duration(milliseconds: 100));
        expect((await local.getAll()).length, equals(0));
        await Future.delayed(Duration(milliseconds: 400));
        expect((await local.getAll()).length, equals(0));
        await Future.delayed(Duration(milliseconds: 400));
        expect((await local.getAll()).length, equals(1));
      });
      test("deferredPresent is true when there are deferred updates", () async {
        remote.isOnline = false;
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 500));
        expect(store.deferredPresent, isTrue);
        remote.isOnline = true;
      });
    });
    group("synchronization functionality", () {
      test("automatic: local additions to remote", () async {
        expect((await remote.getSince(version: 0)).rows.length, equals(0));
        expect((await remote.getSince(version: 0)).version, equals(0));
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 800));
        expect((await remote.getSince(version: 0)).rows.length, equals(1));
        expect((await remote.getSince(version: 0)).version, greaterThan(0));

        // synchronization check
        // version is only updated through synchronization
        expect(await local.getVersion(), equals(0));
        var sync = await store.synchronize();
        expect(sync.length, equals(2));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 0);
        expect(sync[0].pulled, 1);
        expect(sync[1].exception, equals("nothing to sync"));
        expect(await local.getVersion(), equals(await remote.getVersion()));
      });
      test("automatic: local deletes to remote", () async {
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));
        expect((await remote.getSince(version: 0)).rows.length, equals(1));
        store.delete(store.docs[0].id);
        await Future.delayed(Duration(milliseconds: 200));
        var remoteRows = await remote.getSince(version: 0);
        expect(remoteRows.rows.length, equals(1));
        expect(remoteRows.rows[0].id, equals(store.docs[0].id));
        expect(remoteRows.rows[0].data, contains('"archived":true'));

        // synchronization check
        // version is only updated through synchronization
        expect(await local.getVersion(), equals(0));
        var sync = await store.synchronize();
        expect(sync.length, equals(2));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 0);
        expect(sync[0].pulled, 1);
        expect(sync[1].exception, equals("nothing to sync"));
        expect(await local.getVersion(), equals(await remote.getVersion()));
      });
      test("automatic: local modifications to remote", () async {
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));
        expect((await remote.getSince(version: 0)).rows.length, equals(1));
        store.modify(store.docs[0]..age = 18);
        await Future.delayed(Duration(milliseconds: 200));
        var remoteRows = await remote.getSince(version: 0);
        expect(remoteRows.rows.length, equals(1));
        expect(remoteRows.rows[0].id, equals(store.docs[0].id));
        expect(remoteRows.rows[0].data, contains('"age":18'));

        // synchronization check
        // version is only updated through synchronization
        expect(await local.getVersion(), equals(0));
        var sync = await store.synchronize();
        expect(sync.length, equals(2));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 0);
        expect(sync[0].pulled, 1);
        expect(sync[1].exception, equals("nothing to sync"));
        expect(await local.getVersion(), equals(await remote.getVersion()));
      });
      test("on sync: send deferred additions", () async {
        remote.isOnline = false;
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));
        expect((await remote.getSince(version: 0)).rows.length, equals(0));
        remote.isOnline = true;

        expect(await remote.getVersion(), equals(0));

        // synchronization check
        expect(await local.getVersion(), equals(0));
        var sync = await store.synchronize();
        expect(sync.length, equals(3));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 1);
        expect(sync[0].pulled, 0);
        expect(sync[1].pushed, 0);
        expect(sync[1].pulled, 1);
        expect(sync[2].exception, equals("nothing to sync"));
        expect(await local.getVersion(), equals(await remote.getVersion()));
      });
      test("on sync: send deferred deletions", () async {
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));
        await store.synchronize();
        var remoteVersion = await remote.getVersion();
        var localVersion = await local.getVersion();

        remote.isOnline = false;
        store.delete(store.docs[0].id);
        await Future.delayed(Duration(milliseconds: 200));
        expect((await remote.getSince(version: 0)).version, equals(remoteVersion));
        expect((await remote.getSince(version: 0)).version, equals(localVersion));
        remote.isOnline = true;

        expect(await remote.getVersion(), equals(remoteVersion));

        // synchronization check
        expect(await local.getVersion(), equals(localVersion));
        var sync = await store.synchronize();
        expect(sync.length, equals(3));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 1);
        expect(sync[0].pulled, 0);
        expect(sync[1].pushed, 0);
        expect(sync[1].pulled, 1);
        expect(sync[2].exception, equals("nothing to sync"));
        expect(await local.getVersion(), greaterThan(localVersion));
        expect(await remote.getVersion(), equals(await local.getVersion()));
      });
      test("on sync: send deferred modifications", () async {
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));
        await store.synchronize();
        var remoteVersion = await remote.getVersion();
        var localVersion = await local.getVersion();

        remote.isOnline = false;
        store.modify(store.docs[0]..age = 11);
        await Future.delayed(Duration(milliseconds: 200));
        expect((await remote.getSince(version: 0)).version, equals(remoteVersion));
        expect((await remote.getSince(version: 0)).version, equals(localVersion));
        remote.isOnline = true;

        expect(await remote.getVersion(), equals(remoteVersion));

        // synchronization check
        expect(await local.getVersion(), equals(localVersion));
        var sync = await store.synchronize();
        expect(sync.length, equals(3));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 1);
        expect(sync[0].pulled, 0);
        expect(sync[1].pushed, 0);
        expect(sync[1].pulled, 1);
        expect(sync[2].exception, equals("nothing to sync"));
        expect(await local.getVersion(), greaterThan(localVersion));
        expect(await remote.getVersion(), equals(await local.getVersion()));
      });
      test("when there's deferred, all events will be deferred until sync", () async {
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));
        await store.synchronize();
        var remoteVersion = await remote.getVersion();
        var localVersion = await local.getVersion();

        remote.isOnline = false;
        store.modify(store.docs[0]..age = 11);
        await Future.delayed(Duration(milliseconds: 200));
        expect((await remote.getSince(version: 0)).version, equals(remoteVersion));
        expect((await remote.getSince(version: 0)).version, equals(localVersion));
        remote.isOnline = true;
        await Future.delayed(Duration(milliseconds: 200));

        store.add(Person.fromJson({}));
        store.add(Person.fromJson({}));
        store.add(Person.fromJson({}));

        await Future.delayed(Duration(milliseconds: 110));
        expect((await local.getDeferred()).length, equals(4));
      });
      test("deferred changes must keep only the latest changes", () async {
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));
        await store.synchronize();
        var remoteVersion = await remote.getVersion();
        var localVersion = await local.getVersion();

        remote.isOnline = false;
        store.modify(store.docs[0]..age = 11);
        await Future.delayed(Duration(milliseconds: 200));
        expect((await remote.getSince(version: 0)).version, equals(remoteVersion));
        expect((await remote.getSince(version: 0)).version, equals(localVersion));
        remote.isOnline = true;
        await Future.delayed(Duration(milliseconds: 200));

        store.add(Person.fromJson({}));
        store.delete(store.docs[0].id);
        store.modify(store.docs[1]..age = 12);

        store.add(Person.fromJson({}));
        store.add(Person.fromJson({}));

        await Future.delayed(Duration(milliseconds: 110));
        expect((await local.getDeferred()).length, equals(4));
      });
      test("remote additions to local", () async {
        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 11}',
          "id2": '{"id": "id2", "name": "name2", "age": 12}',
          "id3": '{"id": "id3", "name": "name3", "age": 13}',
        });

        var sync = await store.synchronize();
        expect(sync.length, equals(2));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 0);
        expect(sync[0].pulled, 3);
        expect(sync[1].exception, "nothing to sync");

        expect(store.docs.length, equals(3));
        expect(store.docs[0].id, equals("id1"));
        expect(store.docs[0].name, equals("name1"));
        expect(store.docs[0].age, equals(11));
        expect(store.docs[1].id, equals("id2"));
        expect(store.docs[1].name, equals("name2"));
        expect(store.docs[1].age, equals(12));
        expect(store.docs[2].id, equals("id3"));
        expect(store.docs[2].name, equals("name3"));
        expect(store.docs[2].age, equals(13));
      });
      test("remote deletes to local", () async {
        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 11}',
          "id2": '{"id": "id2", "name": "name2", "age": 12}',
          "id3": '{"id": "id3", "name": "name3", "age": 13}',
        });

        await store.synchronize();

        expect(store.docs[0].archived, equals(null));
        expect(store.docs[1].archived, equals(null));

        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 11, "archived": true}',
          "id2": '{"id": "id2", "name": "name2", "age": 12, "archived": true}',
        });

        var sync = await store.synchronize();
        expect(sync.length, equals(2));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 0);
        expect(sync[0].pulled, 2);
        expect(sync[1].exception, "nothing to sync");

        expect(store.docs[0].archived, equals(true));
        expect(store.docs[1].archived, equals(true));
      });
      test("remote modifications to local", () async {
        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 11}',
          "id2": '{"id": "id2", "name": "name2", "age": 12}',
          "id3": '{"id": "id3", "name": "name3", "age": 13}',
        });

        await store.synchronize();

        expect(store.docs[0].age, equals(11));
        expect(store.docs[1].age, equals(12));

        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 111}',
          "id2": '{"id": "id2", "name": "name2", "age": 112}',
        });

        var sync = await store.synchronize();
        expect(sync.length, equals(2));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 0);
        expect(sync[0].pulled, 2);
        expect(sync[1].exception, "nothing to sync");

        expect(store.docs[0].age, equals(111));
        expect(store.docs[1].age, equals(112));
      });
      test("bi-directional", () async {
        remote.isOnline = false;
        store.add(Person.fromJson({"id": "id0"}));
        await Future.delayed(Duration(milliseconds: 200));

        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 11}',
          "id2": '{"id": "id2", "name": "name2", "age": 12}',
          "id3": '{"id": "id3", "name": "name3", "age": 13}',
        });

        remote.isOnline = true;
        await Future.delayed(Duration(milliseconds: 110));

        var sync = await store.synchronize();
        expect(sync.length, equals(3));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 1);
        expect(sync[0].pulled, 3);
        expect(sync[1].exception, equals(null));
        expect(sync[1].pushed, 0);
        expect(sync[1].pulled, 1);
        expect(sync[2].exception, "nothing to sync");

        expect(store.docs[0].id, equals("id0"));
        expect(store.docs[1].id, equals("id1"));
        expect(store.docs[2].id, equals("id2"));
        expect(store.docs[3].id, equals("id3"));
      });
      test("bi-directional with conflicts (local winners)", () async {
        remote.isOnline = false;

        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 11}',
          "id2": '{"id": "id2", "name": "name2", "age": 12}',
          "id3": '{"id": "id3", "name": "name3", "age": 13}',
        });
        await Future.delayed(Duration(milliseconds: 200));
        store.add(Person.fromJson({"id": "id2", "name": "modified-name", "age": 0}));
        await Future.delayed(Duration(milliseconds: 200));
        remote.isOnline = true;
        var sync = await store.synchronize();
        expect(sync.length, equals(3));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 1);
        expect(sync[0].pulled, 2);
        expect(sync[0].conflicts, 1);
        expect(sync[1].exception, equals(null));
        expect(sync[1].pushed, 0);
        expect(sync[1].pulled, 1);
        expect(sync[2].exception, "nothing to sync");

        expect(store.docs[0].name, equals("name1"));
        expect(store.docs[1].name, equals("modified-name"));
        expect(store.docs[2].name, equals("name3"));
      });
      test("bi-directional with conflicts (remote winners)", () async {
        remote.isOnline = false;
        store.add(Person.fromJson({"id": "id1", "age": 11}));
        await Future.delayed(Duration(milliseconds: 200));

        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 111}',
          "id2": '{"id": "id2", "name": "name2", "age": 12}',
          "id3": '{"id": "id3", "name": "name3", "age": 13}',
        });

        remote.isOnline = true;
        await Future.delayed(Duration(milliseconds: 110));

        var sync = await store.synchronize();
        expect(sync.length, equals(2));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, 0);
        expect(sync[0].conflicts, 1);
        expect(sync[0].pulled, 3);
        expect(sync[1].exception, "nothing to sync");

        expect(store.docs[0].age, equals(111));
        expect(store.docs[1].age, equals(12));
        expect(store.docs[2].age, equals(13));
      });
      test("bi-directional with conflicts (some local and some remote winners)", () async {
        remote.isOnline = false;
        store.add(Person.fromJson({"id": "id1", "name": "local-1"}));
        await Future.delayed(Duration(milliseconds: 200));

        await remote.put({
          "id1": '{"id": "id1", "name": "remote-1"}',
          "id2": '{"id": "id2", "name": "remote-2"}',
          "id3": '{"id": "id3", "name": "remote-3"}',
        });

        remote.isOnline = true;
        store.add(Person.fromJson({"id": "id3", "name": "local-3"}));
        store.add(Person.fromJson({"id": "id4", "name": "local-4-newly-added"}));

        await Future.delayed(Duration(milliseconds: 110));
        var sync = await store.synchronize();
        expect(sync.length, equals(3));
        expect(sync[0].exception, equals(null));
        expect(sync[0].pushed, equals(2));
        expect(sync[0].pulled, equals(2));
        expect(sync[0].conflicts, equals(2));
        expect(sync[1].exception, equals(null));
        expect(sync[1].pushed, equals(0));
        expect(sync[1].pulled, equals(2));
        expect(sync[1].conflicts, equals(0));
        expect(sync[2].exception, equals("nothing to sync"));

        expect(store.get("id1").name, equals("remote-1"));
        expect(store.get("id2").name, equals("remote-2"));
        expect(store.get("id3").name, equals("local-3"));
        expect(store.get("id4").name, equals("local-4-newly-added"));
      });
      test("inSync methods correctly tells whether the store is in sync", () async {
        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 11}',
          "id2": '{"id": "id2", "name": "name2", "age": 12}',
          "id3": '{"id": "id3", "name": "name3", "age": 13}',
        });
        expect(await store.inSync(), equals(false));
        await store.synchronize();
        expect(await store.inSync(), equals(true));
        store.add(Person.fromJson({"id": "id1", "name": "modified-name", "age": 0}));
        await Future.delayed(Duration(milliseconds: 150));
        expect(await store.inSync(), equals(false));
        await store.synchronize();
        expect(await store.inSync(), equals(true));
      });
      test("onSyncStart/onSyncEnd functions are called", () async {
        int startCount = 0;
        int endCount = 0;

        store = Store(
          remote: remote,
          local: local,
          modeling: Person.fromJson,
          onSyncStart: () => startCount++,
          onSyncEnd: () => endCount++,
        );

        store.add(Person.fromJson({"id": "id1", "name": "modified-name", "age": 0}));
        await remote.put({
          "id1": '{"id": "id1", "name": "name1", "age": 11}',
          "id2": '{"id": "id2", "name": "name2", "age": 12}',
          "id3": '{"id": "id3", "name": "name3", "age": 13}',
        });
        await store.synchronize();
        await Future.delayed(Duration(milliseconds: 150));

        expect(startCount, equals(2));
        expect(endCount, equals(2));
      });
    });
    group("backup and restore functionality", () {
      test("backup functionality", () async {
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));
        final backupData = await store.backup();
        expect(backupData, isNotNull);
      });
      test("restore functionality", () async {
        store.add(Person.fromJson({}));
        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));
        final backupData = await store.backup();

        store.add(Person.fromJson({}));
        await Future.delayed(Duration(milliseconds: 200));

        // Simulate restoring
        await store.restore(backupData);

        await store.synchronize();

        expect(store.docs.length, equals(2));
      });
    });
  });
}
