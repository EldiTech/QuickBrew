import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_counter.dart';

void main() {
  group('the bundled whole-menu posters', () {
    for (final partner in BrewPartner.values) {
      test('${partner.name} ships boards, each backed by a file on disk', () {
        final boards = BrewWholeMenuBoard.defaultsFor(partner);

        expect(boards, isNotEmpty, reason: 'View whole menu must not be empty');
        for (final board in boards) {
          final path = board.assetPath;
          expect(path, isNotNull, reason: board.id);
          expect(File(path!).existsSync(), isTrue, reason: '$path is missing');
          expect(board.aspectRatio, 9 / 16, reason: '${board.id} is portrait');
        }
      });

      test('${partner.name} boards are in a stable order, ids unique', () {
        final boards = BrewWholeMenuBoard.defaultsFor(partner);

        expect(
          boards.map((board) => board.sort),
          orderedEquals([for (var i = 1; i <= boards.length; i++) i.toDouble()]),
        );
        expect(boards.map((board) => board.id).toSet(), hasLength(boards.length));
      });
    }

    test('an admin upload replaces the bundled boards rather than joining them',
        () {
      const uploaded = BrewWholeMenuBoard(
        id: 'poster',
        title: 'New poster',
        aspectRatio: 9 / 16,
      );

      expect(
        BrewWholeMenuBoard.resolveFor(BrewPartner.a, const [uploaded]),
        [uploaded],
      );
      expect(
        BrewWholeMenuBoard.resolveFor(BrewPartner.a, const []),
        BrewWholeMenuBoard.defaultsFor(BrewPartner.a),
      );
    });
  });
}
