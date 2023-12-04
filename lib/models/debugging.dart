class Debugging {
  static const bool _toPrint = true;

  static void printing(String message) {
    if (_toPrint) {
      print(message);
    }
  }
}
