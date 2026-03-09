import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() async {
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text("Running Network Test..."))),
    ),
  );

  debugPrint('\n\n========== NETWORK DIAGNOSTIC TEST ==========\n');

  // 1. Test Internet Reachability (Google)
  debugPrint('1. Testing Internet (google.com)...');
  try {
    final response = await http
        .get(Uri.parse('https://www.google.com'))
        .timeout(const Duration(seconds: 10));
    debugPrint('   [SUCCESS] Status Code: ${response.statusCode}');
  } catch (e) {
    debugPrint('   [FAILURE] Could not connect to Google: $e');
  }

  // 2. Test Backend Reachability (Standard)
  final backendUrl =
      'https://almudeer.royaraqamia.com/health'; // Using health endpoint
  debugPrint('\n2. Testing Backend ($backendUrl)...');
  try {
    final response = await http
        .get(Uri.parse(backendUrl))
        .timeout(const Duration(seconds: 10));
    debugPrint('   [SUCCESS] Status Code: ${response.statusCode}');
    debugPrint('   [BODY] ${response.body}');
    if (response.statusCode == 200 || response.statusCode == 404) {
      // Connection successful
    }
  } catch (e) {
    debugPrint('   [FAILURE] Standard connection failed: $e');
    if (e is HandshakeException) {
      debugPrint(
        '   >>> HANDSHAKE EXCEPTION DETECTED: This indicates an SSL/Certificate issue.',
      );
    } else if (e is SocketException) {
      debugPrint('   >>> SOCKET EXCEPTION: Network unreachable or DNS failed.');
      debugPrint('   OS Error: ${e.osError}');
    }
  }

  // 3. Test Backend with Insecure HTTP Client (Bypass SSL)
  debugPrint('\n3. Testing Backend with SSL Bypass...');
  try {
    final client = HttpClient()
      ..badCertificateCallback = ((X509Certificate cert, String host, int port) {
        debugPrint(
          '   [SSL] Bypass certificate: ${cert.subject} issued by ${cert.issuer}',
        );
        return true; // Trust everything
      });

    final request = await client.postUrl(
      Uri.parse(
        'https://almudeer.royaraqamia.com/api/admin/subscription/validate-key',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write('{"key": "UDEER-D9A1-5B39-345C"}');
    final response = await request.close();
    debugPrint(
      '   [SUCCESS] SSL Bypass Connection Established. Status Code: ${response.statusCode}',
    );

    // Read response
    final responseBody = await response
        .transform(SystemEncoding().decoder)
        .join();
    debugPrint(
      '   Body snippet: ${responseBody.substring(0, responseBody.length > 100 ? 100 : responseBody.length)}...',
    );
  } catch (e) {
    debugPrint('   [FAILURE] Even SSL Bypass failed: $e');
  }

  debugPrint('\n========== TEST COMPLETE ==========\n\n');
}
