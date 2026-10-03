import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';

/// Which input a rejection belongs under.
///
/// Firebase answers with one error for the whole call, but the reader is looking
/// at three fields — an address that is already taken is a fact about the email
/// field, and hanging it in a banner over the form makes them hunt for what to
/// change. [form] is for the ones that are genuinely about neither field:
/// no network, rate limiting, sign-up switched off in the console.
enum BrewAuthField { email, password, form }

/// A rejection, already translated out of Firebase's vocabulary.
///
/// The wording lives here rather than in the screen for the same reason
/// form_rules.dart owns its messages: the sentence a failure produces is part of
/// the failure, and a screen that writes its own copy for `email-already-in-use`
/// is a second place that has to be kept honest.
class BrewAuthFailure {
  const BrewAuthFailure(this.field, this.message);

  /// Maps a [FirebaseAuthException.code] to the field it belongs under and what
  /// to say. Deliberately a pure function of the code string so it can be
  /// tested without a Firebase app anywhere in sight.
  ///
  /// Only the codes `createUserWithEmailAndPassword` actually throws are listed.
  /// Everything else lands on the fallback, which says the true thing — the
  /// account was not created — instead of guessing at a reason.
  factory BrewAuthFailure.fromCode(String code) => switch (code) {
    'email-already-in-use' => const BrewAuthFailure(
      BrewAuthField.email,
      'That email already has an account. Log in instead.',
    ),
    'invalid-email' => const BrewAuthFailure(
      BrewAuthField.email,
      'That address is missing a @ or a domain.',
    ),
    // The local rule already asks for more characters than Firebase's floor of
    // six, so this only arrives for a password the server dislikes for some
    // other reason — hence "stronger" rather than restating a length.
    'weak-password' => const BrewAuthFailure(
      BrewAuthField.password,
      'Pick a stronger password.',
    ),
    // Log-in's three rejections, and all one sentence on purpose. Modern
    // projects have email-enumeration protection on, which collapses
    // `user-not-found` and `wrong-password` into `invalid-credential` precisely
    // so the server stops confirming which addresses exist — answering "no
    // account with that email" here would hand back the fact the setting exists
    // to withhold. It lands on the form rather than under a field because it is
    // genuinely about neither one: either could be the wrong half.
    'invalid-credential' || 'user-not-found' || 'wrong-password' =>
      const BrewAuthFailure(
        BrewAuthField.form,
        'That email and password do not match an account.',
      ),
    'user-disabled' => const BrewAuthFailure(
      BrewAuthField.form,
      'That account has been switched off.',
    ),
    // A misconfigured project, not a mistake the reader made. Said plainly
    // rather than dressed up as their problem.
    'operation-not-allowed' || 'admin-restricted-operation' =>
      const BrewAuthFailure(
        BrewAuthField.form,
        'Sign-up is switched off for this project right now.',
      ),
    'network-request-failed' => const BrewAuthFailure(
      BrewAuthField.form,
      'No connection. Check the network and try again.',
    ),
    'too-many-requests' => const BrewAuthFailure(
      BrewAuthField.form,
      'Too many attempts. Wait a moment, then try again.',
    ),
    _ => const BrewAuthFailure(
      BrewAuthField.form,
      'That did not go through. Try again.',
    ),
  };

  final BrewAuthField field;

  /// A sentence, in the body voice — the same register as a validation message,
  /// because from where the reader sits it is the same kind of answer.
  final String message;
}

/// A live session: who is signed in, as the screens need them.
///
/// A deliberately thin read of Firebase's `User`. The home screen wants a first
/// name for the greeting and a uid to look orders up by, and giving it the whole
/// `User` would put the SDK's surface — `delete`, `getIdToken`, `reload` — one
/// dot away from a widget that has no business calling any of it.
class BrewSession {
  const BrewSession({required this.uid, this.name, this.email});

  /// Null when nobody is signed in, so `authStateChanges` and `userChanges` map
  /// straight onto `BrewSession?` without the screens testing two things.
  static BrewSession? of(User? user) => user == null
      ? null
      : BrewSession(uid: user.uid, name: user.displayName, email: user.email);

  final String uid;

  /// Whatever they typed into the sign-up form's Name field. Null on an account
  /// created before that field existed, or if `updateDisplayName` failed after
  /// the account itself was made — see [BrewAuth.createAccount].
  final String? name;

  final String? email;

  /// The greeting says one name, not a full one: "Good morning, David" is what
  /// the counter would say, and "Good morning, David Espino" is what a form
  /// letter says.
  ///
  /// Null rather than a stand-in when there is no name to use. The greeting then
  /// drops the address entirely instead of opening with "Good morning, there",
  /// which is worse than not naming anyone.
  String? get firstName {
    final full = name?.trim();
    if (full == null || full.isEmpty) return null;
    return full.split(RegExp(r'\s+')).first;
  }
}

/// The account layer: everything the forms need from Firebase Auth, and nothing
/// else.
///
/// It exists so the screens never import `firebase_auth`. A screen's job ends at
/// "the form is locally valid"; what happens after that is one call that either
/// succeeds or comes back with a [BrewAuthFailure] it knows how to display.
class BrewAuth {
  BrewAuth(this._auth);

  final FirebaseAuth _auth;

  /// Who is signed in, now and whenever that changes. Null means nobody.
  ///
  /// [FirebaseAuth.userChanges] rather than `authStateChanges`: sign-up sets the
  /// display name *after* the account exists, and `authStateChanges` does not
  /// fire for a profile edit. On that stream the home screen would open with a
  /// nameless greeting and only find the name on the next cold start.
  ///
  /// The first event arrives without a round trip — Firebase restores a
  /// persisted session from disk — so a returning reader is known to be signed
  /// in well before the splash finishes extracting.
  Stream<BrewSession?> get sessions => _auth.userChanges().map(BrewSession.of);

  /// The session as of right now, without waiting for [sessions] to tick.
  BrewSession? get current => BrewSession.of(_auth.currentUser);

  /// Brings Firebase up, or returns null if it cannot come up.
  ///
  /// Null rather than a throw, because the splash and the landing screen owe
  /// nothing to Firebase and should not be taken down by a missing
  /// google-services.json — on the web build, for instance, there is no native
  /// config for [Firebase.initializeApp] to read. The failure then surfaces at
  /// the one place it matters, on the form, instead of as a black screen at
  /// launch.
  static Future<BrewAuth?> connect() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return BrewAuth(FirebaseAuth.instance);
    } catch (error) {
      debugPrint('QuickBrew → Firebase unavailable: $error');
      return null;
    }
  }

  /// Creates the account and leaves the reader signed in, which is what
  /// `createUserWithEmailAndPassword` does on success — a sign-up that then
  /// asked them to log in would be asking twice for the same two facts.
  ///
  /// Returns null on success, or the failure to put on the form.
  Future<BrewAuthFailure?> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      // The name is the only one of the three fields Firebase does not store on
      // its own. It is set after the account exists rather than as a condition
      // of it: an account that is real but unnamed is recoverable, whereas
      // treating a failed rename as a failed sign-up would leave the reader
      // being told nothing happened while their account sits on the server.
      await credential.user?.updateDisplayName(name);
      return null;
    } on FirebaseAuthException catch (error) {
      return BrewAuthFailure.fromCode(error.code);
    } catch (error) {
      // Plugin and channel errors reach here. The reader gets the same sentence
      // as an unrecognised code, because from the form's side it is the same
      // outcome; the detail goes to the log for whoever is debugging.
      debugPrint('QuickBrew → sign-up failed: $error');
      return BrewAuthFailure.fromCode('');
    }
  }

  /// Signs an existing account in. Returns null on success, or the failure to
  /// put on the form.
  ///
  /// Nothing is returned on success because there is nothing the form needs: the
  /// session arrives on [sessions], which is what decides where the reader goes
  /// next. A form that received the user here would be a second thing holding an
  /// opinion about who is signed in.
  Future<BrewAuthFailure?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (error) {
      return BrewAuthFailure.fromCode(error.code);
    } catch (error) {
      debugPrint('QuickBrew → log-in failed: $error');
      return BrewAuthFailure.fromCode('');
    }
  }

  /// Sends a password reset link to [email]. Returns null on success, or the
  /// failure to report.
  Future<BrewAuthFailure?> sendPasswordResetEmail({
    required String email,
  }) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (error) {
      return BrewAuthFailure.fromCode(error.code);
    } catch (error) {
      debugPrint('QuickBrew → password reset failed: $error');
      return BrewAuthFailure.fromCode('');
    }
  }

  /// Ends the session. [sessions] emits null, and that is what moves the reader,
  /// so this reports nothing.
  Future<void> signOut() => _auth.signOut();
}
