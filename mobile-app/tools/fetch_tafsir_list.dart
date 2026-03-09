import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  try {
    final response = await http.get(
      Uri.parse('http://api.quran-tafseer.com/tafseer'),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      for (var item in data) {
        debugPrint(
          'ID: ${item['id']} - Name: ${item['name']} - Book: ${item['book_name']}',
        );
      }
    } else {
      debugPrint('Failed to load tafsir list: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error: $e');
  }
}
