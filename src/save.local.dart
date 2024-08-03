import 'dart:convert';
import 'package:hive/hive.dart';
import 'dart:async';

final _versionKey = 'meta:version';
final _deferredKey = 'meta:deferred';

class Dump {
  Map<String, String> main;
  Map<String, String> meta;
  Dump(this.main, this.meta);
}

class SaveLocal {
  String name;

  Future<Box<String>> mainBox;
  Future<Box<String>> metaBox;

  SaveLocal(this.name)
      : mainBox = Hive.openBox("$name:main"),
        metaBox = Hive.openBox("$name:meta");

  Future<void> put(Map<String, String> entries) async {
    return await (await mainBox).putAll(entries);
  }

  Future<String> get(String key) async {
    return (await (await mainBox).get(key)) ?? "";
  }

  Future<Iterable<String>> getAll() async {
    return (await mainBox).values;
  }

  Future<int> getVersion() async {
    return int.parse((await (await metaBox).get(_versionKey)) ?? "0");
  }

  Future<void> putVersion(int versionValue) async {
    return await (await metaBox).put(_versionKey, versionValue.toString());
  }

  Future<Map<String, int>> getDeferred() async {
    return jsonDecode(await (await metaBox).get(_deferredKey) ?? "{}");
  }

  Future<void> putDeferred(Map<String, int> deferred) async {
    return (await metaBox).put(_deferredKey, jsonEncode(deferred));
  }

  Future<Dump> dump() async {
    return Dump((await mainBox).toMap() as Map<String, String>,
        (await metaBox).toMap() as Map<String, String>);
  }

  Future<void> restore(Dump dump) async {
    await (await mainBox).clear();
    await (await metaBox).clear();
    await (await mainBox).putAll(dump.main);
    await (await metaBox).putAll(dump.meta);
  }
}
