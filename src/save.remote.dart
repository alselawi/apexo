import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class _ServerResponse {
  late bool success;
  late String output;
  _ServerResponse(String source) {
    try {
      var decoded = jsonDecode(source);
      success = decoded["success"];
      output = decoded["output"];
    } catch (_) {
      success = false;
      output = "Server responded with non-json $source";
    }
  }
}

class _Row {
  String id;
  String data;
  int? ts;
  _Row(this.id, this.data, this.ts);
}

class _VersionedResult {
  int version;
  List<_Row> rows;
  _VersionedResult(this.version, this.rows);
}

class SaveRemote {
  final String baseUrl;
  final String token;
  final String table;

  bool isOnline = true;

  SaveRemote(
      {required this.baseUrl, required this.token, required this.table}) {
    checkOnline();
  }

  Future<void> checkOnline() async {
    try {
      final response = await http.head(Uri.parse(baseUrl));
      if (response.statusCode != 200) {
        isOnline = false;
      } else {
        isOnline = true;
      }
    } catch (id) {
      isOnline = false;
    }
  }

  void retryConnection() {
    Timer.periodic(Duration(seconds: 5), (timer) {
      if (isOnline) {
        timer.cancel();
      } else {
        checkOnline();
      }
    });
  }

  Future<_VersionedResult> getSince({int version = 0}) async {
    int page = 0;
    bool nextPage = true;
    int fetchedVersion = 0;
    List<_Row> result = [];

    while (nextPage) {
      final url = '$baseUrl/$table/$version/$page';
      _ServerResponse response;
      try {
        response = _ServerResponse((await http.get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
          },
        ))
            .body);
      } catch (e) {
        checkOnline();
        return _VersionedResult(0, []);
      }

      if (!response.success) {
        return _VersionedResult(0, []);
      }

      final output = jsonDecode(response.output) as Map<String, dynamic>;
      List rows = output['rows'];
      nextPage = rows.isNotEmpty && version != 0;
      fetchedVersion = output['version'];
      var formattedRows =
          rows.map((row) => _Row(row["id"], row["data"], row["ts"]));
      result.addAll(formattedRows);
      page += 1;
    }

    return _VersionedResult(fetchedVersion, result);
  }

  Future<int> getVersion() async {
    final url = '$baseUrl/$table/0/Infinity';
    _ServerResponse response;

    try {
      response = _ServerResponse((await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ))
          .body);
    } catch (e) {
      checkOnline();
      return 0;
    }

    if (response.success) {
      return jsonDecode(response.output)['version'];
    } else {
      return 0;
    }
  }

  Future<void> put(Map<String, String> data) async {
    final String url = '$baseUrl/$table';
    try {
      await http.put(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      );
    } catch (e) {
      checkOnline();
      throw e;
    }
  }
}
