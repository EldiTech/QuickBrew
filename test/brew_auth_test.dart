import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_auth.dart';

/// The translation from Firebase's error codes to what the form says.
///
/// Worth its own test rather than only the widget ones: this is the layer that
/// decides which of three fields a rejection belongs to, and getting that wrong
/// sends the reader to edit something that was never the problem. It is a pure
/// function of the code string, so none of this needs a Firebase app.
void main() {
  test('a taken or malformed address is the email field\'s problem', () {
    for (final code in ['email-already-in-use', 'invalid-email']) {
      expect(BrewAuthFailure.fromCode(code).field, BrewAuthField.email);
    }
  });

  test('a rejected password is the password field\'s problem', () {
    expect(
      BrewAuthFailure.fromCode('weak-password').field,
      BrewAuthField.password,
    );
  });

  test('the project\'s own faults belong to no field', () {
    const codes = [
      'operation-not-allowed',
      'admin-restricted-operation',
      'network-request-failed',
      'too-many-requests',
    ];
    for (final code in codes) {
      expect(BrewAuthFailure.fromCode(code).field, BrewAuthField.form);
    }
  });

  test('an unrecognised code says the true thing and blames nothing', () {
    final failure = BrewAuthFailure.fromCode('some-code-that-did-not-exist');

    expect(failure.field, BrewAuthField.form);
    expect(failure.message, 'That did not go through. Try again.');
  });

  test('every message is a sentence, because the fields render them as one', () {
    const codes = [
      'email-already-in-use',
      'invalid-email',
      'weak-password',
      'operation-not-allowed',
      'admin-restricted-operation',
      'network-request-failed',
      'too-many-requests',
      '',
    ];
    for (final code in codes) {
      final message = BrewAuthFailure.fromCode(code).message;
      expect(message, isNotEmpty, reason: code);
      expect(message.endsWith('.'), isTrue, reason: code);
      // Never the raw code, and never Firebase's own phrasing.
      expect(message.toLowerCase(), isNot(contains('firebase')), reason: code);
    }
  });

  test('firstName returns first name of multi-word user names', () {
    const session = BrewSession(
      uid: 'u1',
      email: 'john@example.com',
      name: 'John Michael Doe',
    );
    expect(session.firstName, 'John');
  });
}
