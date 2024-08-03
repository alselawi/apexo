import 'model.dart';
import 'observable.dart';

void main() {
  Observable<MyClass> men = Observable([
    MyClass.fromJson({}),
    MyClass.fromJson({}),
    MyClass.fromJson({}),
    MyClass.fromJson({}),
    MyClass.fromJson({})
  ], 100);

  men.observe((diffs) {
    print(diffs);
  });

  men.target[0].age = 1222;
  men.target[2].age = 122;
}
