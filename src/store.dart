import 'dart:async';
import 'dart:convert';
import 'Model.dart';
import 'ObservableList.dart';
import 'SaveLocal.dart';
import 'SaveRemote.dart';
import 'Debouncer.dart';

typedef ModellingFunc<G> = G Function(Map<String, dynamic> input);

class SyncResult {
  int? pushed;
  int? pulled;
  int? conflicts;
  String? exception;
  SyncResult({this.pushed, this.pulled, this.conflicts, this.exception});
  toString() {
    return "pushed: $pushed, pulled: $pulled, conflicts: $conflicts, exception: $exception";
  }
}

class Store<G extends Model> {
  late Future<void> loaded;
  final Function? onSyncStart;
  final Function? onSyncEnd;
  final ObservableList<G> observableObject;
  final Set<String> changes = Set();
  final SaveLocal local;
  final SaveRemote remote;
  final int debounceMS;
  late Debouncer _debouncer;
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
      : observableObject = ObservableList() {
    // setting up debouncer
    _debouncer = Debouncer(
      milliseconds: debounceMS,
    );

    // loading from local
    loaded = _loadFromLocal();

    // setting up observers
    observableObject.observe((events) {
      List<String> ids = events.map((e) => e.id).toList();
      changes.addAll(ids);
      _debouncer.run(() {
        _processChanges();
      });
    });
  }

  Future<void> _loadFromLocal() async {
    Iterable<String> all = await local.getAll();
    Iterable<G> modeled = all.map((x) => modeling(_deSerialize(x)));

    observableObject.silently(() {
      observableObject.clear();
      observableObject.addAll(modeled.toList());
    });
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
    onSyncStart?.call();
    lastProcessChanges = DateTime.now().millisecondsSinceEpoch;

    Map<String, String> toWrite = {};
    Map<String, int> toDefer = {};
    List<String> changesToProcess = [...changes.toList()];

    for (String element in changesToProcess) {
      G item = observableObject.firstWhere((x) => x.id == element);
      String serialized = _serialize(item);
      toWrite[element] = serialized;
      toDefer[element] = lastProcessChanges;
    }

    await local.put(toWrite);
    Map<String, int> lastDeferred = await local.getDeferred();

    if (remote.isOnline && lastDeferred.length == 0) {
      try {
        await remote.put(toWrite);
        changes.clear();
        onSyncEnd?.call();
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
    onSyncEnd?.call();
  }

  Future<SyncResult> _syncTry() async {
    if (remote.isOnline == false) return SyncResult(exception: "remote server is offline");
    try {
      int localVersion = await local.getVersion();
      int remoteVersion = await remote.getVersion();

      Map<String, int> deferred = await local.getDeferred();
      int conflicts = 0;

      if (localVersion == remoteVersion && deferred.length == 0) {
        return SyncResult(exception: "nothing to sync");
      }

      // fetch updates since our local version
      VersionedResult remoteUpdates = await remote.getSince(version: localVersion);

      List<int> remoteLosersIndices = [];

      // check conflicts: last write wins
      deferred.removeWhere((dfID, dfTS) {
        int remoteConflictIndex = remoteUpdates.rows.indexWhere((r) => r.id == dfID);
        if (remoteConflictIndex == -1) {
          return false;
        }
        int remoteTS = remoteUpdates.rows[remoteConflictIndex].ts ?? remoteVersion;
        if (remoteConflictIndex == -1) {
          // no conflicts
          return false;
        } else if (dfTS > remoteTS) {
          // local update wins
          conflicts++;
          remoteLosersIndices.add(remoteConflictIndex);
          return false;
        } else {
          // remote update wins
          // return true to remove this item from deferred
          conflicts++;
          return true;
        }
      });

      // remove losers from remote updates
      remoteLosersIndices.forEach((index) {
        remoteUpdates.rows.removeAt(index);
      });

      Map<String, String> toLocalWrite = Map.fromEntries(remoteUpdates.rows.map((r) => MapEntry(r.id, r.data)));

      Map<String, String> toRemoteWrite = Map.fromEntries(
          await Future.wait(deferred.entries.map((entry) async => MapEntry(entry.key, await local.get(entry.key)))));

      if (toLocalWrite.length > 0) await local.put(toLocalWrite);
      if (toRemoteWrite.length > 0) await remote.put(toRemoteWrite);

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
          pulled: toLocalWrite.length, pushed: toRemoteWrite.length, conflicts: conflicts, exception: null);
    } catch (e, stacktrace) {
      print("Error during synchronization: $e");
      print(stacktrace);
      return SyncResult(exception: e.toString());
    }
  }

  //// ----------------------------- Public API --------------------------------

  /// Syncs the local database with the remote database
  Future<List<SyncResult>> synchronize() async {
    lastProcessChanges = DateTime.now().millisecondsSinceEpoch;
    onSyncStart?.call();
    List<SyncResult> tries = [];
    while (true) {
      SyncResult result = await _syncTry();
      tries.add(result);
      if (result.exception != null) break;
    }
    onSyncEnd?.call();
    return tries;
  }

  //// Returns true if the local database is in sync with the remote database
  Future<bool> inSync() async {
    if (deferredPresent) return false;
    return await local.getVersion() == await remote.getVersion();
  }

  /// Reloads the store from the local database
  Future<void> reload() async {
    await _loadFromLocal();
  }

  /// Returns a list of all the documents in the local database
  List<G> get docs {
    return [...observableObject.docs];
  }

  /// gets a document by id
  G get(String id) {
    return docs.firstWhere((x) => x.id == id);
  }

  /// gets a document index by id
  int getIndex(String id) {
    return docs.indexWhere((x) => x.id == id);
  }

  /// adds a document
  void add(G item) {
    observableObject.add(item);
  }

  /// adds a list of documents
  void addAll(List<G> items) {
    observableObject.addAll(items);
  }

  /// modifies a document
  void modify(G item) {
    observableObject.modify(item);
  }

  /// archives a document by id (the concept of deletion is not supported here)
  void archive(String id) {
    int index = getIndex(id);
    if (index == -1) return;
    observableObject.modify(docs[index]..archived = true);
  }

  /// un-archives a document by id (the concept of deletion is not supported here)
  void unarchive(String id) {
    int index = getIndex(id);
    if (index == -1) return;
    observableObject.modify(docs[index]..archived = false);
  }

  /// archives a document by id (the concept of deletion is not supported here)
  void delete(String id) {
    archive(id);
  }

  /// returns a dump that can be used to restore the store to a specific state
  Future<Dump> backup() async {
    return await local.dump();
  }

  /// restores the store to a specific state using a dump
  Future<void> restore(Dump dump) async {
    await remote.checkOnline();
    if (remote.isOnline == false) {
      throw Exception("remote server is offline");
    }
    await local.clear();
    await remote.clear();
    await remote.put(dump.main);
    await synchronize();
    await _loadFromLocal();
  }
}
