extension MyIntExtensions on int {
  String get intToBinary => toRadixString(2).padLeft(8, "0");
}