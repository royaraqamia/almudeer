import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final logFile = File('fetch_debug.log');
  await logFile.writeAsString('Script started\n');

  try {
    final client = HttpClient();
    // ID 1 (Al-Muyassar) - Surah 1
    final url = Uri.parse('http://api.quran-tafseer.com/tafseer/1/1');
    await logFile.writeAsString('Requesting $url\n', mode: FileMode.append);

    final request = await client.getUrl(url);
    final response = await request.close();

    await logFile.writeAsString(
      'Response Status: ${response.statusCode}\n',
      mode: FileMode.append,
    );

    if (response.statusCode == 200) {
      final content = await response.transform(utf8.decoder).join();
      await logFile.writeAsString(
        'Received content length: ${content.length}\n',
        mode: FileMode.append,
      );

      // Write to temporary JSON
      File('test_surah_1.json').writeAsStringSync(content);
      await logFile.writeAsString(
        'Saved to test_surah_1.json\n',
        mode: FileMode.append,
      );
    } else {
      await logFile.writeAsString('Failed request\n', mode: FileMode.append);
    }
  } catch (e, st) {
    await logFile.writeAsString(
      'Error: $e\nStack: $st\n',
      mode: FileMode.append,
    );
  }
  await logFile.writeAsString('Script finished\n', mode: FileMode.append);
}
