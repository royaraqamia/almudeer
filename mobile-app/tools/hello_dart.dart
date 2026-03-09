import 'dart:io';

void main() {
  File('hello_dart.txt').writeAsStringSync('Hello from Dart!');
}
