import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the three version floors in `pubspec.yaml`, because each one is a
/// mistake this package was created having already seen.
///
/// A caret is a FLOOR: it cannot reach BELOW itself, which is the whole reason
/// these floors are asserted. A sibling plugin once declared a stale `dowel`
/// caret, and copying it here would let a solver satisfy this package with an
/// older CLI whenever something else in the graph wanted one. Likewise the
/// `environment` block is inherited from `magic` rather than chosen, and
/// copying a sibling's older block would claim support this package cannot
/// honour.
///
/// A test rather than a comment because a comment cannot fail.
void main() {
  late final String pubspec;

  setUpAll(() {
    pubspec = File('pubspec.yaml').readAsStringSync();
  });

  group('pubspec floors', () {
    test('the SDK constraints are inherited from magic, not from a sibling', () {
      expect(pubspec, contains('sdk: ">=3.13.0 <4.0.0"'));
      expect(pubspec, contains('flutter: ">=3.47.0"'));

      // The block a sibling plugin declares. Copying it is the specific error.
      expect(pubspec, isNot(contains('sdk: ">=3.6.0 <4.0.0"')));
      expect(pubspec, isNot(contains('flutter: ">=3.27.0"')));
    });

    test('the dowel floor is the stable release, not a stale pre-1.0 one', () {
      expect(pubspec, contains('dowel: ^1.0.0'));
      expect(pubspec, isNot(contains('^0.0.21')));
      expect(pubspec, isNot(contains('^0.0.20')));
      expect(pubspec, isNot(contains('^0.0.8')));
      expect(pubspec, isNot(contains('^0.0.13')));
    });

    // The floor names the release this package is verified against.
    test('magic is pinned to the release this package is verified against', () {
      expect(pubspec, contains('magic: ^1.0.0'));
      expect(pubspec, isNot(contains('magic: ^0.')));
    });
  });
}
