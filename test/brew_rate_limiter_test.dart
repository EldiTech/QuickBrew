import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/brew_rate_limiter.dart';

/// The lockout rules, and that both forms actually stop at them.
///
/// The clock is a variable the tests move by hand, so a fifteen-minute window
/// costs nothing to run.
void main() {
  late DateTime now;
  late BrewRateLimiter limiter;

  setUp(() {
    now = DateTime(2026, 10, 13, 9);
    limiter = BrewRateLimiter(clock: () => now);
  });

  void fail(int times, [String key = 'k']) {
    for (var i = 0; i < times; i++) {
      limiter.recordFailure(key);
    }
  }

  test('four rejections leave the form open; the fifth locks it', () {
    fail(4);
    expect(limiter.retryAfter('k'), isNull);

    fail(1);
    expect(limiter.retryAfter('k'), const Duration(seconds: 30));
  });

  test('the lock lifts once the wait has passed', () {
    fail(5);
    now = now.add(const Duration(seconds: 29));
    expect(limiter.retryAfter('k'), const Duration(seconds: 1));

    now = now.add(const Duration(seconds: 1));
    expect(limiter.retryAfter('k'), isNull);
  });

  test('each lockout in a run doubles, up to the cap', () {
    final waits = <Duration>[];
    for (var round = 0; round < 7; round++) {
      fail(5);
      final wait = limiter.retryAfter('k')!;
      waits.add(wait);
      now = now.add(wait);
    }

    expect(waits, const [
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 4),
      Duration(minutes: 8),
      Duration(minutes: 15),
      Duration(minutes: 15),
    ]);
  });

  test('rejections older than the window are forgotten, streak and all', () {
    fail(5);
    now = now.add(const Duration(seconds: 30));
    fail(4);

    now = now.add(const Duration(minutes: 16));
    fail(4);
    expect(limiter.retryAfter('k'), isNull, reason: 'the old four expired');

    fail(1);
    expect(
      limiter.retryAfter('k'),
      const Duration(seconds: 30),
      reason: 'a quiet window resets the doubling too',
    );
  });

  test('getting in clears the slate', () {
    fail(4);
    limiter.recordSuccess('k');
    fail(4);
    expect(limiter.retryAfter('k'), isNull);
  });

  test('keys are counted apart', () {
    fail(5, 'sign-in');
    expect(limiter.retryAfter('sign-in'), isNotNull);
    expect(limiter.retryAfter('sign-up'), isNull);
  });

  test('the lockout message names the wait in words a reader uses', () {
    String say(Duration wait) => BrewAuthFailure.lockedOut(wait).message;

    expect(say(const Duration(seconds: 30)),
        'Too many attempts. Try again in 30 seconds.');
    expect(say(const Duration(milliseconds: 400)),
        'Too many attempts. Try again in 1 second.');
    expect(say(const Duration(seconds: 61)),
        'Too many attempts. Try again in 2 minutes.');
    expect(say(const Duration(minutes: 1)),
        'Too many attempts. Try again in 1 minute.');
    expect(BrewAuthFailure.lockedOut(const Duration(seconds: 5)).field,
        BrewAuthField.form);
  });

  group('BrewAuth', () {
    late MockFirebaseAuth firebase;
    late BrewAuth auth;
    late int calls;

    setUp(() {
      firebase = MockFirebaseAuth();
      auth = BrewAuth(firebase, limiter: limiter);
      calls = 0;
    });

    void reject(Symbol method, String code) {
      whenCalling(Invocation.method(method, null))
          .on(firebase)
          .thenThrow(FirebaseAuthException(code: code));
    }

    Future<BrewAuthFailure?> logIn() {
      calls++;
      return auth.signIn(email: 'dave@work.com', password: 'flatwhite1');
    }

    test('five wrong passwords lock log-in without asking Firebase again',
        () async {
      reject(#signInWithEmailAndPassword, 'invalid-credential');
      for (var i = 0; i < 5; i++) {
        expect((await logIn())!.message,
            'That email and password do not match an account.');
      }

      final locked = await logIn();
      expect(locked!.message, 'Too many attempts. Try again in 30 seconds.');
      expect(calls, 6);

      // Sign-up keeps its own count.
      final signUp = await auth.createAccount(
        name: 'Dave',
        email: 'new@work.com',
        password: 'flatwhite1',
      );
      expect(signUp, isNull);
    });

    test('a dropped connection is not held against the reader', () async {
      reject(#signInWithEmailAndPassword, 'network-request-failed');
      for (var i = 0; i < 10; i++) {
        expect((await logIn())!.message,
            'No connection. Check the network and try again.');
      }
    });

    test('five rejected sign-ups lock sign-up', () async {
      reject(#createUserWithEmailAndPassword, 'email-already-in-use');
      Future<BrewAuthFailure?> signUp() => auth.createAccount(
        name: 'Dave',
        email: 'dave@work.com',
        password: 'flatwhite1',
      );

      for (var i = 0; i < 5; i++) {
        expect((await signUp())!.field, BrewAuthField.email);
      }
      expect((await signUp())!.message,
          'Too many attempts. Try again in 30 seconds.');
    });
  });
}
