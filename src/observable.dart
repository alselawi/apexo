import 'dart:convert';
import 'dart:async';
import 'model.dart';
import "uuid.dart";
import "hash.dart";

typedef Callback = void Function(Set<String>);

class Observer {
  final String id = uuid();
  final Callback callback;
  Observer(Callback cb) : callback = cb;
}

class Observable<D extends Doc> {
  final List<D> target;
  final List<Observer> listeners = [];
  late Timer timerRef;
  final List<StackTrace> errors = [];
  final int interval;
  late List<dynamic> snapshot;
  late int signature;
  bool silent = false;
  Observable(this.target, this.interval) {
    String jsonString = jsonEncode(_cc(target));
    snapshot = jsonDecode(jsonString);
    signature = fastHash(jsonString);

    var t = Timer.periodic(Duration(milliseconds: interval), (Timer timer) {
      String __jsonString = jsonEncode(_cc(target));
      List<dynamic> __snapshot = jsonDecode(__jsonString);
      int __signature = fastHash(__jsonString);

      if (__signature == signature) return;
      if (silent) {
        silent = false; // re-listening
        return;
      }

      Set<String> diffs = Set();

      for (var i = 0; i < __snapshot.length; i++) {
        dynamic itemThen = snapshot[i];
        dynamic itemNow = __snapshot[i];
        if (jsonEncode(itemThen) != jsonEncode(itemNow)) {
          diffs.add(itemNow["id"]);
        }
      }

      for (var listener in listeners) {
        try {
          listener.callback(diffs);
        } catch (id, stacktrace) {
          errors.add(stacktrace);
        }
      }

      signature = __signature;
      snapshot = __snapshot;
    });
    timerRef = t;
  }

  List<D> _cc(List<D> input) {
    return [...input]..sort(_comparator);
  }

  int _comparator(D a, D b) => a.id.compareTo(b.id);

  observe(Callback callback) {
    var observer = Observer(callback);
    listeners.add(observer);
    return observer.id;
  }

  unObserve(String id) {
    listeners.removeWhere((item) => item.id == id);
  }

  stop() {
    listeners.clear();
    timerRef.cancel();
  }
}
