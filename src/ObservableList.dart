import 'dart:async';
import 'Model.dart';
import 'uuid.dart';

typedef OEventCallback = void Function(List<OEvent>);

class CustomError {
  final String message;
  final StackTrace stackTrace;
  CustomError(this.message, this.stackTrace);
}

class Observer {
  final String id = uuid();
  final OEventCallback callback;
  Observer(OEventCallback cb) : callback = cb;
}

enum EventType {
  add,
  modify,
  remove,
}

class OEvent {
  final EventType type;
  final int index;
  final String id;
  OEvent.add(this.index, this.id) : type = EventType.add;
  OEvent.modify(this.index, this.id) : type = EventType.modify;
  OEvent.remove(this.index, this.id) : type = EventType.remove;
}

class ObservableList<T extends Model> {
  final List<T> _list = [];
  final StreamController<List<OEvent>> _controller = StreamController<List<OEvent>>.broadcast();
  final List<Observer> _observers = [];
  final List<CustomError> errors = [];
  Stream<List<OEvent>> get _stream => _controller.stream;
  int _silent = 0;

  ObservableList() {
    _stream.listen((events) {
      _observers.forEach((observer) {
        try {
          observer.callback(events);
        } catch (message, stackTrace) {
          errors.add(CustomError(message.toString(), stackTrace));
        }
      });
    });
  }

  /// --------- small abstractions ---------

  /**
   * returns the first item that matches the test
   */
  T firstWhere(bool Function(T) test) {
    return _list.firstWhere(test);
  }

/**
 * returns the first index that matches the test
 */
  int indexWhere(bool Function(T) test) {
    return _list.indexWhere(test);
  }

  /**
   * returns the index of the item with the given id
   */
  int indexOfId(String id) {
    return _list.indexWhere((item) => item.id == id);
  }

  /// --------- actions/modifiers ---------
  /**
   * adds an item to the list
   */
  void add(T item) {
    _list.add(item);
    if (_silent == 0) _controller.add([OEvent.add(_list.length - 1, item.id)]);
  }

  /**
   * adds a list of items to the list
  */
  void addAll(List<T> items) {
    int startIndex = _list.length;
    _list.addAll(items);
    List<OEvent> events = [];
    for (int i = 0; i < items.length; i++) {
      events.add(OEvent.add(startIndex + i, items[i].id));
    }
    if (_silent == 0) _controller.add(events);
  }

  /**
   * removes an item from the list
   */
  void remove(item) {
    int index = indexOfId(item.id);
    if (index >= 0 && index < _list.length) {
      String id = _list[index].id;
      _list.removeAt(index);
      if (_silent == 0) _controller.add([OEvent.remove(index, id)]);
    }
  }

  /**
   * updates an item in the list
   */
  void modify(T item) {
    int index = indexOfId(item.id);
    if (index >= 0 && index < _list.length) {
      _list[index] = item;
      if (_silent == 0) _controller.add([OEvent.modify(index, item.id)]);
    }
  }

  /**
   * clears the list
   */
  void clear() {
    _list.clear();
    if (_silent == 0) _controller.add([OEvent.remove(-1, '')]);
  }

  /// --------- observations API ---------

  /**
   * registers a new observer and returns a unique id
   * the id can be used to un-register the observer
   */
  String observe(OEventCallback callback) {
    int existing = _observers.indexWhere((o) => o.callback == callback);
    if (existing > -1) {
      return _observers[existing].id;
    }
    Observer observer = Observer(callback);
    _observers.add(observer);
    return observer.id;
  }

  /**
   * un-registers an observer by id
   */
  void unObserve(String id) {
    _observers.removeWhere((observer) => observer.id == id);
  }

  /**
   * stops all observations and closes the stream
   */
  void dispose() {
    _silent = 999999999999999999;
    _observers.clear();
    _controller.close();
  }

  /**
   * runs a function in silence, i.e. without triggering any observers
   */
  void silently(void Function() fn) {
    _silent++;
    try {
      fn();
    } catch (e, stacktrace) {
      errors.add(CustomError(e.toString(), stacktrace));
    }
    _silent--;
  }

  List<T> get docs => List.unmodifiable(_list);
}
