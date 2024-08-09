import 'uuid.dart';

class Model {
  String id = uuid();
  bool? archived;

  Model.fromJson(Map<String, dynamic> json) {
    id = json["id"] ?? uuid();
    archived = json["archived"];
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (id != uuid()) json['id'] = id;
    if (archived != null) json['archived'] = archived;
    return json;
  }
}


/**
 ********* Example usage

class MyClass extends Doc {
  String name = '';
  int age = 0;

  MyClass.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    name = json["name"] ?? name;
    age = json["age"] ?? age;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = MyClass.fromJson({});
    if (name != d.name) json['name'] = name;
    if (age != d.age) json['age'] = age;
    return json;
  }

  get ageInDays => age * 365;
}
*/