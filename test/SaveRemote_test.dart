import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import '../src/SaveRemote.dart';

void main() async {
  SaveRemote remote = SaveRemote(baseUrl: "http://127.0.0.1:8787", token: "null", table: "appointments");

  setUp(() async {
    await remote.clear();

    Uri server = Uri.parse("http://127.0.0.1:8787/appointments");
    try {
      await http.get(server);
    } catch (e) {
      throw Exception("Apexo-database is not running");
    }

    await http.delete(server, headers: {
      'Authorization': 'Bearer null',
    });
  });

  group("SaveRemote", () {
    test('should get the version of the database', () async {
      final version = await remote.getVersion();
      expect(version, equals(0));
    });

    test("set as online/offline", () async {
      remote.isOnline = false;
      await remote.checkOnline();
      expect(remote.isOnline, equals(true));
    });

    test("upload data", () async {
      int initialVersion = await remote.getVersion();
      expect(initialVersion, equals(0));
      await remote.put({
        "id1": "data1",
        "id2": "data2",
        "id3": "data3",
      });
      int laterVersion = await remote.getVersion();
      expect(laterVersion, greaterThan(initialVersion));
    });

    test("get data", () async {
      await remote.put({
        "id0": "data0",
        "id1": "data1",
        "id2": "data2",
        "id3": "data3",
      });
      var data = await remote.getSince(version: 0);
      expect(data.version, greaterThan(0));
      expect(data.rows.length, greaterThan(0));
      expect(data.rows.firstWhere((row) => row.id == "id0").data, equals("data0"));
      expect(data.rows.firstWhere((row) => row.id == "id1").data, equals("data1"));
      expect(data.rows.firstWhere((row) => row.id == "id2").data, equals("data2"));
    });

    test("get data with non-zero version", () async {
      await remote.put({"id1": "data1"});
      await remote.put({"id2": "data2"});
      var initialData = await remote.getSince(version: 0);
      await remote.put({"id3": "data3"});
      var laterData = await remote.getSince(version: initialData.version);
      expect(laterData.version, greaterThan(initialData.version));
      expect(laterData.rows.length, equals(1));
      expect(laterData.rows[0].data, equals("data3"));
      expect(laterData.rows[0].id, equals("id3"));
    });

    test("put empty data", () async {
      await expectLater(remote.put({}), throwsA("JSON body is empty"));
    });

    test("upload/get large data", () async {
      int initialVersion = await remote.getVersion();
      Map<String, String> largeData = {};
      for (int i = 0; i < 3500; i++) {
        largeData["id$i"] = "data$i";
      }
      await remote.put(largeData);

      int laterVersion = await remote.getVersion();
      expect(laterVersion, greaterThan(initialVersion));

      var res = await remote.getSince(version: initialVersion);
      expect(res.version, greaterThan(initialVersion));
      expect(res.rows.length, equals(largeData.length));
    });

    test("upload and retrieve data consistency", () async {
      await remote.put({
        "id100": "data100",
        "id101": "data101",
      });
      var data = await remote.getSince(version: 0);
      expect(data.rows.any((row) => row.id == "id100" && row.data == "data100"), isTrue);
      expect(data.rows.any((row) => row.id == "id101" && row.data == "data101"), isTrue);
    });
  });
}
