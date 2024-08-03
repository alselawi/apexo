import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'model.dart';
import 'observable.dart';
import 'save.local.dart';
import 'save.remote.dart';

typedef ModellingFunc<G> = G Function(Map<String, dynamic> input);

class SyncResult {
  int? pushed;
  int? pulled;
  int? conflicts;
  String? exception;
  SyncResult({this.pushed, this.pulled, this.conflicts, this.exception});
}

class Store<G extends Doc> {
  late Future<void> loaded;
  final Function? onSyncStart;
  final Function? onSyncEnd;
  final Observable<G> observableObject;
  final Set<String> changes = Set();
  final SaveLocal local;
  final SaveRemote remote;
  final int debounceMS;
  late ModellingFunc<G> modeling;

  bool deferredPresent = false;
  int lastProcessChanges = 0;

  Store(
      {required this.local,
      required this.remote,
      required this.modeling,
      this.debounceMS = 100,
      this.onSyncStart,
      this.onSyncEnd})
      : observableObject = Observable([], debounceMS) {
    // loading from local
    loaded = _loadFromLocal();

    // setting up observers
    observableObject.observe((ids) {
      changes.addAll(ids);
      int nextRun = lastProcessChanges +
          debounceMS -
          DateTime.now().millisecondsSinceEpoch;
      Timer(Duration(milliseconds: max(nextRun, 0)), () {
        _processChanges();
      });
    });
  }

  Future<void> _loadFromLocal() async {
    var all = await local.getAll();
    var modeled = all.map((x) => modeling(_deSerialize(x)));

    observableObject.silent = true;
    observableObject.target.clear();
    observableObject.target.addAll(modeled);
    return;
  }

  String _serialize(G input) {
    return jsonEncode(input);
  }

  Map<String, dynamic> _deSerialize(String input) {
    return jsonDecode(input);
  }

  _processChanges() async {
    if (changes.length == 0) return;
    onSyncStart!();
    lastProcessChanges = DateTime.now().millisecondsSinceEpoch;

    Map<String, String> toWrite = {};
    Map<String, int> toDefer = {};
    List<String> changesToProcess = [...changes.toList()];

    for (String element in changesToProcess) {
      G item = observableObject.target.firstWhere((x) => x.id == element);
      String serialized = _serialize(item);
      toWrite[element] = serialized;
      toDefer[element] = lastProcessChanges;
    }

    await local.put(toWrite);
    Map<String, int> lastDeferred = await local.getDeferred();

    if (remote.isOnline && lastDeferred.length > 0) {
      try {
        await remote.put(toWrite);
        changes.clear();
        onSyncEnd!();
        return;
      } catch (e) {
        print("Will defer updates, due to error during sending.");
        print(e);
      }
    }

    /**
     * If we reached here, it means that its either
     * 1. we're offline
     * 2. there was an error during sending updates
     * 3. there are already deferred updates
     */
    await local.putDeferred({}
      ..addAll(lastDeferred)
      ..addAll(toDefer));
    deferredPresent = true;
    changes.clear();
    onSyncEnd!();
  }

  _syncTry() async {
    if (remote.isOnline == false)
      return SyncResult(exception: "remote server is offline");
    try {
      int localVersion = await local.getVersion();
      int remoteVersion = await remote.getVersion();
      var deferred = await local.getDeferred();
      int conflicts = 0;

      if (localVersion == remoteVersion && deferred.length == 0) {
        return SyncResult(exception: "nothing to sync");
      }

      // fetch updates since our local version
      var remoteUpdates = await remote.getSince(version: localVersion);

      // check conflicts: last write wins
      deferred.removeWhere((dfID, dfTS) {
        int remoteConflictIndex =
            remoteUpdates.rows.indexWhere((r) => r.id == dfID);
        int remoteTS =
            remoteUpdates.rows[remoteConflictIndex].ts ?? remoteVersion;
        if (remoteConflictIndex == -1) {
          // no conflicts
          return false;
        } else if (dfTS > remoteTS) {
          // local update wins
          conflicts++;
          return false;
        } else {
          // remote update wins
          // return true to remove this item from deferred
          conflicts++;
          return true;
        }
      });

      Map<String, String> toLocalWrite = Map.fromEntries(
          remoteUpdates.rows.map((r) => MapEntry(r.id, r.data)));

      Map<String, String> toRemoteWrite = Map.fromEntries(await Future.wait(
          deferred.entries.map((entry) async =>
              MapEntry(entry.key, await local.get(entry.key)))));

      await local.put(toLocalWrite);
      await remote.put(toRemoteWrite);

      // reset deferred
      await local.putDeferred({});
      deferredPresent = false;

      // set local version to the version given by the current request
      // this might be outdated as soon as this functions ends
      // that's why this function will run on a while loop (below)
      await local.putVersion(remoteUpdates.version);

      // but if we had deferred updates then the remoteUpdates.version is outdated
      // so we need to fetch the latest version again
      // however, we should not do this in the same run since there might be updates
      // from another client between the time we fetched the remoteUpdates and the
      // time we sent deferred updates
      // so every sync should be followed by another sync
      // until the versions match
      // this is why there's another sync method below

      await _loadFromLocal();
      return SyncResult(
          pulled: toLocalWrite.length,
          pushed: toRemoteWrite.length,
          conflicts: conflicts,
          exception: null);
    } catch (e) {
      return SyncResult(exception: e.toString());
    }
  }

  //// ----------------------------- Public API --------------------------------

  Future<List<SyncResult>> synchronize() async {
    lastProcessChanges = DateTime.now().millisecondsSinceEpoch;
    onSyncStart!();
    List<SyncResult> tries = [];
    while (true) {
      var result = await _syncTry();
      tries.add(result);
      if (result.exception != null) break;
    }
    onSyncEnd!();
    return tries;
  }

  Future<bool> inSync() async {
    if (deferredPresent) return false;
    return await local.getVersion() == await remote.getVersion();
  }

  Future<void> reload() async {
    await _loadFromLocal();
  }

  get list {
    return observableObject.target;
  }

  get copy {
    return [...observableObject.target];
  }

  get(String id) {
    return observableObject.target.firstWhere((x) => x.id == id);
  }

  getIndex(String id) {
    return observableObject.target.indexWhere((x) => x.id == id);
  }

  add(G item) {
    observableObject.target.add(item);
  }

  archive(String id) {
    var index = getIndex(id);
    if (index == -1) return;
    observableObject.target[index].archived = true;
  }

  unarchive(String id) {
    var index = getIndex(id);
    if (index == -1) return;
    observableObject.target[index].archived = false;
  }

  delete(String id) {
    archive(id);
  }

  Future<Dump> backup() async {
    return await local.dump();
  }

  restore(Dump dump) async {
    await remote.checkOnline();
    if (remote.isOnline == false) {
      return throw Exception("remote server is offline");
    }
    await local.restore(dump);
    await remote.put(dump.main);
    await synchronize(); // to get the latest version
  }
}
