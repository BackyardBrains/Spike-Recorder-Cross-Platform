import 'dart:typed_data';

import 'package:collection/collection.dart';

/// Checks for new and old samples equality to decide whether to process samples
/// again or not when samples are updated.
bool Function(List<int> list1, List<int> list2) checkforSamplesEquality =
    const ListEquality<int>().equals;
