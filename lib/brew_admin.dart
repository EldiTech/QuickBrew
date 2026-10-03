import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'brew_auth.dart';
import 'brew_counter.dart';
import 'brew_menu_seed.dart';

/// Who someone signed in is allowed to do, past reading the menu and their own
/// orders.
///
/// A plain reader is [customer] — every account starts here. [admin] configures
/// the one store a super admin assigned it to. [superadmin] configures both and
/// is the only role that can assign the other two. There is no fourth role and
/// no partial admin: a store either belongs to an admin or it does not, and
/// there are exactly two stores to belong to.
enum BrewRole {
  customer,
  admin,
  superadmin;

  /// Unrecognised and missing values both read as [customer] — the role
  /// nobody has to be granted.
  static BrewRole parse(Object? value) => switch (value) {
    'admin' => BrewRole.admin,
    'superadmin' => BrewRole.superadmin,
    _ => BrewRole.customer,
  };

  String get storedValue => name;

  bool get isCustomer => this == BrewRole.customer;

  /// Either kind of admin, which is who [BrewAdmin.users] and the admin
  /// screens exist for.
  bool get canConfigureStores => this != BrewRole.customer;

  String get label => switch (this) {
    BrewRole.customer => 'Customer',
    BrewRole.admin => 'Admin',
    BrewRole.superadmin => 'Super admin',
  };
}

/// What `users/{uid}` says about one account.
///
/// The rest of the app already has [BrewSession](brew_auth.dart) for who is
/// signed in; this is the fact Firebase Auth itself has no field for — what
/// they are allowed to configure — plus the email and name copied down beside
/// it so the users screen can list an account without a second round trip per
/// row.
class BrewUserProfile {
  const BrewUserProfile({
    required this.uid,
    required this.email,
    this.name,
    required this.role,
    this.assignedStore,
    this.createdAt,
  });

  /// Null only when there is no document at all.
  ///
  /// Every other field is allowed to be missing, [email] included. That is
  /// deliberate and it is the difference between an admin who works and one
  /// who does not: the first super admin is created by hand in the Firebase
  /// console — there is no in-app path to that role, by design — and a
  /// hand-made document is very often just `{ role: "superadmin" }`. Requiring
  /// an email here would read that as no profile at all, and the account would
  /// be shown the customer app with nothing anywhere saying why. The uid is the
  /// identity, and it comes from the document's own name; email and name are
  /// display copy.
  static BrewUserProfile? read(String uid, Map<String, Object?>? data) {
    if (data == null) return null;

    return BrewUserProfile(
      uid: uid,
      email: switch (data['email']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => null,
      },
      name: switch (data['name']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => null,
      },
      role: BrewRole.parse(data['role']),
      assignedStore: BrewPartner.values
          .where((partner) => partner.id == data['assignedStore'])
          .firstOrNull,
      createdAt: switch (data['createdAt']) {
        final Timestamp value => value.toDate(),
        final DateTime value => value,
        _ => null,
      },
    );
  }

  final String uid;

  /// Null on a profile written by hand without one. Never assumed present —
  /// see [read].
  final String? email;

  final String? name;
  final BrewRole role;

  /// Null for a customer and for a super admin, who is not tied to one store.
  /// Set for an admin — the store an invite named when the account claimed it.
  final BrewPartner? assignedStore;

  /// When this profile document was first written. Null on a hand-made one —
  /// the same super admin document [read]'s doc comment describes — and on
  /// the sliver of a moment between [BrewAdmin.ensureProfile]'s write landing
  /// and the server timestamp it asked for actually resolving.
  final DateTime? createdAt;

  /// What a row in the users list is titled by: the email if the profile has
  /// one, else the name, else the uid. Not pretty in the last case, but never
  /// absent and never the same string for two accounts — which is what a list
  /// of people needs from the line that identifies each one.
  String get identifier => email ?? name ?? uid;
}

/// A standing offer of a role, waiting for the person it names to sign up or
/// log in and claim it.
///
/// This is the whole mechanism behind "the super admin assigns the
/// credentials": nothing on this client can reach into Firebase Auth and
/// create somebody else's account, so a super admin instead leaves a note
/// under the invited email's name, and [BrewAdmin.ensureProfile] reads it the
/// first time that email is signed in.
class BrewInvite {
  const BrewInvite({
    required this.email,
    required this.role,
    this.assignedStore,
    required this.used,
  });

  static BrewInvite? read(String email, Map<String, Object?>? data) {
    if (data == null) return null;
    return BrewInvite(
      email: email,
      role: BrewRole.parse(data['role']),
      assignedStore: BrewPartner.values
          .where((partner) => partner.id == data['assignedStore'])
          .firstOrNull,
      used: data['used'] == true,
    );
  }

  final String email;
  final BrewRole role;
  final BrewPartner? assignedStore;
  final bool used;
}

/// The admin layer: everything the admin screens read and write, and nothing
/// else.
///
/// The same bargain [BrewAuth](brew_auth.dart) and
/// [BrewCounter](brew_counter.dart) strike — no admin screen imports
/// `cloud_firestore` directly. What makes this layer different is that it
/// writes: [setShopOpen] and the menu methods are the "something that is not
/// this app" the original firestore.rules comment promised, now that the admin
/// side *is* part of this app. The rules in firestore.rules are the actual
/// authority throughout; every check duplicated here (in [inviteAdmin], for
/// instance) exists only to fail early with a sentence instead of a bare
/// permission-denied.
class BrewAdmin {
  BrewAdmin(this._db);

  /// Null when Firestore cannot be reached at all — see [BrewCounter.connect]
  /// for why that is a null return rather than a throw.
  static BrewAdmin? connect() {
    try {
      return BrewAdmin(FirebaseFirestore.instance);
    } catch (error) {
      debugPrint('QuickBrew → admin layer unavailable: $error');
      return null;
    }
  }

  final FirebaseFirestore _db;

  String _currentUid(String fallbackUid) {
    String? currentUid;
    try {
      currentUid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      currentUid = null;
    }
    assert(
      currentUid == null || currentUid == fallbackUid,
      'User-owned Firestore access must use the authenticated uid.',
    );
    return currentUid ?? fallbackUid;
  }

  static const _users = 'users';
  static const _invites = 'invites';
  static const _shops = 'shops';
  static const _menu = 'menu';
  static const _addOns = 'addons';
  static const _orders = 'orders';

  /// The key an email is filed under, in both the invites collection and every
  /// rule that has to find it again — see `myEmailKey()` in firestore.rules.
  /// Stated once so the two sides can never drift apart on casing.
  static String _key(String email) => email.trim().toLowerCase();

  /// The signed-in account's own admin facts, live. Null before the document
  /// exists — the moment between a session starting and [ensureProfile]
  /// finishing — and for as long as Firestore is unreachable.
  Stream<BrewUserProfile?> profile(String uid) {
    final ownerUid = _currentUid(uid);
    return _db
        .collection(_users)
        .doc(ownerUid)
        .snapshots()
        .map((doc) => BrewUserProfile.read(ownerUid, doc.data()))
        .handleError((Object error) {
          debugPrint('QuickBrew → profile unavailable: $error');
        });
  }

  /// Makes sure `users/{uid}` exists, the first time this account is ever
  /// seen signed in.
  ///
  /// A plain sign-up becomes an ordinary customer. One whose email matches a
  /// pending invite instead claims the role and store that invite names, and
  /// the invite is marked used in the same batch — so a link cannot be
  /// claimed twice, including by two accounts racing to sign up with the same
  /// address. firestore.rules re-derives and checks all of this independently;
  /// this method is what makes the write, not what makes it legal.
  ///
  /// A no-op once the document exists, so it is safe to call on every login,
  /// not only the first one.
  ///
  /// Reports nothing and throws nothing. Every step here can be refused —
  /// rules that have not been deployed yet deny the very first read — and a
  /// refusal must not escape: this is called from a session listener that
  /// cannot await it, so a thrown [FirebaseException] would surface as an
  /// unhandled async error and take out the frame rather than the profile.
  /// The reader is left on the customer app, which is the safe reading of "we
  /// could not establish that this account is an admin".
  Future<void> ensureProfile({
    required String uid,
    required String email,
    String? name,
  }) async {
    // Firestore rejects an empty document id outright, so an account with no
    // address on it cannot be looked up in a collection keyed by one. Nothing
    // to claim, and no invite that could be addressed to it.
    final key = _key(email);
    if (key.isEmpty) {
      debugPrint('QuickBrew → no email on $uid; not claiming any invite');
    }

    try {
      final ownerUid = _currentUid(uid);
      final userRef = _db.collection(_users).doc(ownerUid);
      final existing = await userRef.get();
      if (existing.exists) return;

      final inviteRef = key.isEmpty
          ? null
          : _db.collection(_invites).doc(key);
      final invite = await inviteRef?.get();
      final inviteData = invite?.data();
      final pending = invite != null &&
          invite.exists &&
          inviteData != null &&
          inviteData['used'] != true;

      // Read out of the invite while it is still known non-null under
      // `pending`, rather than inline in the map literal below — chaining a
      // ternary straight into a map's index access reads fine but is one
      // token away from ambiguous, and this is a write nobody should have to
      // re-derive the precedence of.
      final role = pending
          ? BrewRole.parse(inviteData['role']).storedValue
          : BrewRole.customer.storedValue;
      final assignedStore = pending ? inviteData['assignedStore'] : null;

      final batch = _db.batch();
      batch.set(userRef, {
        'uid': ownerUid,
        'email': email,
        'name': ?name,
        'role': role,
        'assignedStore': assignedStore,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (pending && inviteRef != null) {
        batch.update(inviteRef, {'used': true});
      }
      await batch.commit();
    } catch (error) {
      // Named for the most likely cause by a wide margin. Every path through
      // this method needs `users/{uid}` to be readable and writable by its own
      // account, which is a rule that has to be deployed before it is true —
      // see the users match in firestore.rules.
      debugPrint(
        'QuickBrew → could not establish a profile for $uid: $error\n'
        'QuickBrew → if this says permission-denied, deploy firestore.rules: '
        'firebase deploy --only firestore:rules',
      );
    }
  }

  /// Every account with a profile, for the super admin's roster. Admins and
  /// the super admin sort ahead of the customers among them — the two kinds of
  /// row a super admin actually came to this screen to find — then
  /// alphabetically by email within each.
  Stream<List<BrewUserProfile>> users() {
    return _db
        .collection(_users)
        .snapshots()
        .map((snapshot) {
          final people = [
            for (final doc in snapshot.docs) ?BrewUserProfile.read(doc.id, doc.data()),
          ];
          people.sort((a, b) {
            if (a.role != b.role) return b.role.index.compareTo(a.role.index);
            return a.identifier.compareTo(b.identifier);
          });
          return people;
        })
        .handleError((Object error) {
          debugPrint('QuickBrew → users unavailable: $error');
        });
  }

  /// Invites nobody has claimed yet, oldest first — the super admin's view of
  /// "who have I asked that hasn't shown up".
  Stream<List<BrewInvite>> pendingInvites() {
    return _db
        .collection(_invites)
        .where('used', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          final invites = [
            for (final doc in snapshot.docs) ?BrewInvite.read(doc.id, doc.data()),
          ];
          invites.sort((a, b) => a.email.compareTo(b.email));
          return invites;
        })
        .handleError((Object error) {
          debugPrint('QuickBrew → invites unavailable: $error');
        });
  }

  /// Creates a working admin account for [store], there and then.
  ///
  /// The super admin picks the password and hands it over — which is what makes
  /// this "create an admin" rather than an invitation to become one.
  ///
  /// ## Why a second Firebase app
  ///
  /// `createUserWithEmailAndPassword` does not just create an account, it signs
  /// that account *in* — replacing the session on whichever [FirebaseAuth]
  /// instance it was called on. Called on the default instance it would throw
  /// the super admin out of their own app and leave them logged in as the admin
  /// they just made. So the account is created on a second, throwaway
  /// [FirebaseApp] built from the same options: its auth instance is a separate
  /// session, the new account is signed into *that*, and the default app never
  /// notices. The throwaway is deleted in `finally` so a repeated call does not
  /// collide with a name that already exists.
  ///
  /// The profile document is written from the super admin's own session, not the
  /// new one, because the super admin is the only role the rules let assign a
  /// role — see the users match in firestore.rules.
  ///
  /// Returns null on success, or the sentence to put on the form.
  Future<String?> createAdmin({
    required String email,
    required String password,
    required BrewPartner store,
  }) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Enter an email address.';

    FirebaseApp? provisioner;
    try {
      provisioner = await Firebase.initializeApp(
        name: _provisionerApp,
        options: Firebase.app().options,
      );
      final credential = await FirebaseAuth.instanceFor(app: provisioner)
          .createUserWithEmailAndPassword(email: trimmed, password: password);

      final uid = credential.user?.uid;
      if (uid == null) {
        // No uid means no document can be written, and an Auth account with no
        // profile is a customer who cannot be told why. Said plainly rather
        // than reported as success.
        return 'That account was created but could not be set up. Check the '
            'users list.';
      }

      // The name is left unset deliberately: it is theirs to choose, and
      // guessing one from an email address puts a wrong name on their greeting.
      await _db.collection(_users).doc(uid).set({
        'uid': uid,
        'email': trimmed,
        'role': BrewRole.admin.storedValue,
        'assignedStore': store.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } on FirebaseAuthException catch (error) {
      // Reuses the sign-up wording the create-account form already uses, so
      // "that email already has an account" reads the same in both places.
      return BrewAuthFailure.fromCode(error.code).message;
    } catch (error) {
      debugPrint('QuickBrew → could not create an admin for $trimmed: $error');
      return 'That did not go through. Try again.';
    } finally {
      // Signed out *and* deleted, in that order. Deleting alone would leave the
      // new account's session persisted on disk under this app's name, for the
      // next call to restore before it overwrites it — harmless, but it means a
      // second account's credentials sitting in storage for no reason. The app
      // itself has to go too, or the next call finds the name taken.
      if (provisioner != null) {
        try {
          await FirebaseAuth.instanceFor(app: provisioner).signOut();
        } catch (error) {
          debugPrint('QuickBrew → provisioner sign-out failed: $error');
        }
        try {
          await provisioner.delete();
        } catch (error) {
          debugPrint('QuickBrew → could not dispose the provisioner app: $error');
        }
      }
    }
  }

  /// The name of the throwaway [FirebaseApp] used by [createAdmin]. Anything
  /// other than the default app's name works; this one says why it exists.
  static const _provisionerApp = 'quickbrew-provisioner';

  /// Rewrites what one account may configure: promoting, demoting, reassigning
  /// a store, and correcting the name shown beside it — the super admin's edit,
  /// in one write.
  ///
  /// Merged rather than set outright. `email` and `createdAt` are not this
  /// form's to restate — the address in particular belongs to Firebase Auth and
  /// this screen cannot change it — and a plain `set` would silently drop both,
  /// which for `email` means the row loses the very line that identifies it (see
  /// [BrewUserProfile.identifier]).
  ///
  /// [store] is only meaningful for [BrewRole.admin] and is cleared for the
  /// other two roles rather than left behind. A stale `assignedStore` on a
  /// demoted admin grants nothing — `isAdminFor` in firestore.rules checks the
  /// role first — but it reads on the users screen as though the demotion only
  /// half happened, and it would come back to life if that account were ever
  /// made an admin again.
  ///
  /// Returns null on success, or the sentence to show.
  Future<String?> setUserStanding({
    required String uid,
    required BrewRole role,
    BrewPartner? store,
    String? name,
  }) async {
    // An admin of nowhere is the one combination this cannot store: it is the
    // shape a hand-edited console document arrives in, the dashboard has to say
    // "No store is assigned to this account yet" for it, and there is no reason
    // for a form with a store picker on it to produce another one.
    if (role == BrewRole.admin && store == null) {
      return 'Pick the store this admin runs.';
    }

    final trimmed = name?.trim();
    try {
      await _db.collection(_users).doc(uid).set({
        'uid': uid,
        // Empty is stored as null rather than as '', so clearing the field puts
        // the account back to having no name — which [BrewUserProfile.read]
        // already treats as absent — instead of leaving a blank string that
        // prints as an empty line where a name goes.
        'name': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
        'role': role.storedValue,
        'assignedStore': role == BrewRole.admin ? store?.id : null,
      }, SetOptions(merge: true));
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not update $uid: $error');
      return 'That did not go through. Try again.';
    }
  }

  /// Removes an account's record, and with it every role and store it held.
  ///
  /// What this deliberately does not do — because it cannot — is delete the
  /// Firebase Auth account. Nothing on a client may delete somebody else's
  /// sign-in; that needs the Admin SDK behind a server. So the person can still
  /// log in afterwards, and what they get is the customer app: [ensureProfile]
  /// builds them a plain `customer` document the next time they appear, exactly
  /// as it does for a fresh signup, and the invite that first made them an
  /// admin was marked used the day they claimed it, so it cannot re-grant
  /// anything. Removing the sign-in itself is a trip to the Firebase console,
  /// and the sheet that calls this says so rather than implying otherwise.
  ///
  /// A super admin's own record is not deletable — firestore.rules refuses it
  /// — because there is no in-app path back to that role, so the last one
  /// deleting themselves would leave nobody able to grant it again.
  ///
  /// Returns null on success, or the sentence to show.
  Future<String?> deleteUser(String uid) async {
    try {
      await _db.collection(_users).doc(uid).delete();
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not remove $uid: $error');
      return 'That did not go through. Try again.';
    }
  }

  /// The super admin assigning credentials: a note left under an email
  /// address, naming the one store it will be an admin for as soon as that
  /// address next signs in or logs in. Returns a sentence for the form on
  /// failure, or null once the invite is written.
  Future<String?> inviteAdmin({
    required String email,
    required BrewPartner store,
  }) async {
    final key = _key(email);
    if (key.isEmpty) return 'Enter an email address.';

    try {
      await _db.collection(_invites).doc(key).set({
        'role': BrewRole.admin.storedValue,
        'assignedStore': store.id,
        'used': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (error) {
      debugPrint('QuickBrew → invite to $key failed: $error');
      return 'That did not go through. Try again.';
    }
  }

  /// Withdraws an offer nobody has claimed yet — the super admin changed
  /// their mind about who should run a store, or mistyped the address.
  Future<void> revokeInvite(String email) {
    return _db.collection(_invites).doc(_key(email)).delete();
  }

  /// Brings both `shops/{id}` documents into existence, once.
  ///
  /// Until they exist the cards read "Hours unavailable", which is the truthful
  /// reading of an empty collection but is not much use to an admin who has to
  /// guess that tapping Configure is what creates the record. This writes the
  /// built-in name and description as the starting point and leaves `open`
  /// alone — an absent `open` is "nobody has said", and seeding it to false
  /// would have the app assert both shops are shut on the strength of a
  /// migration rather than a decision.
  ///
  /// Existing documents are untouched: each field is written only if the
  /// document is missing entirely, so a shop already renamed by an admin does
  /// not get reset on the next launch.
  ///
  /// [only] limits the seed to the stores the caller is actually allowed to
  /// write. It is not an optimisation: the rules in firestore.rules let a plain
  /// admin write one shop, so a seed that always walked both would take a
  /// permission-denied on the other every time that admin opened the dashboard.
  /// Passing the caller's own stores keeps the loop inside what it may do.
  /// Omitting it seeds both, which is the super admin's case.
  Future<void> ensureShops({Iterable<BrewPartner>? only}) async {
    for (final partner in only ?? BrewPartner.values) {
      // Scoped per shop rather than around the loop: one shop being refused or
      // unreachable should not stop the other from being created.
      try {
        final ref = _db.collection(_shops).doc(partner.id);
        final existing = await ref.get();
        if (existing.exists) continue;
        await ref.set({
          'name': partner.name,
          'description': partner.description,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        debugPrint('QuickBrew → could not seed ${partner.id}: $error');
      }
    }
  }

  /// Flips whether a store is taking orders. What the home screen's status
  /// mark and [BrewCounter.shops] read back.
  ///
  /// Returns null on success, or the sentence to show — like every other write
  /// on this layer, and unlike the raw future this used to hand back. A refused
  /// write is the ordinary case here rather than an exotic one: the rules let a
  /// plain admin write one shop, so the wrong admin reaching the wrong store,
  /// or any admin reaching either while offline, throws. Uncaught, out of a
  /// future nothing awaited, that surfaced as an unhandled async error — the
  /// toggle stayed exactly as it was, said nothing, and the reader's only
  /// evidence that their shop had not opened was the word on the card not
  /// changing.
  Future<String?> setShopOpen(BrewPartner partner, bool open) async {
    try {
      await _db
          .collection(_shops)
          .doc(partner.id)
          .set({'open': open}, SetOptions(merge: true));
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not set ${partner.id} open=$open: $error');
      return 'That did not go through. Try again.';
    }
  }

  /// Null clears the logo, which is what puts the shop back on its monogram —
  /// see `_ShopMark` in home_screen.dart.
  Future<void> setShopLogo(BrewPartner partner, String? logoUrl) {
    return _db.collection(_shops).doc(partner.id).set({
      'logoUrl': logoUrl,
    }, SetOptions(merge: true));
  }

  /// The shop's own name and line about itself.
  ///
  /// An empty string is stored as null rather than as `''`, so clearing the
  /// field puts the card back on [BrewPartner]'s built-in copy instead of
  /// printing a blank where a name goes.
  Future<void> setShopIdentity(
    BrewPartner partner, {
    required String name,
    required String description,
  }) {
    return _db.collection(_shops).doc(partner.id).set({
      'name': name.trim().isEmpty ? null : name.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
    }, SetOptions(merge: true));
  }

  /// The ceiling on an encoded logo, in characters of base64.
  ///
  /// A Firestore document may not exceed 1 MiB *in total*, and that budget also
  /// has to cover the name, the description, the hours and the field names
  /// themselves. 700 KB leaves a wide margin and is still far more than a
  /// downscaled square logo needs — a 512px JPEG at quality 75 encodes to
  /// something like 60–110 KB. The limit exists so an oversized pick is
  /// refused with a sentence rather than rejected by the server with an
  /// INVALID_ARGUMENT nobody can act on.
  static const maxLogoChars = 700 * 1024;

  /// Stores an uploaded logo as base64 on the shop document. Null clears it.
  ///
  /// Returns null on success, or the sentence to show. Base64 rather than
  /// Cloud Storage because this build has no Storage bucket wired up and a
  /// downscaled square logo is small enough to live in the document that
  /// already describes the shop — see [maxLogoChars] for where that stops
  /// being true.
  Future<String?> setShopLogoBase64(
    BrewPartner partner,
    Uint8List? bytes,
  ) async {
    if (bytes == null) {
      try {
        await _db.collection(_shops).doc(partner.id).set({
          'logoBase64': null,
        }, SetOptions(merge: true));
        return null;
      } catch (error) {
        debugPrint('QuickBrew → could not clear ${partner.id} logo: $error');
        return 'That did not go through. Try again.';
      }
    }

    final encoded = base64Encode(bytes);
    if (encoded.length > maxLogoChars) {
      final kb = (encoded.length / 1024).round();
      return 'That image is too large at ${kb}KB. Pick a smaller one.';
    }

    try {
      await _db.collection(_shops).doc(partner.id).set({
        'logoBase64': encoded,
      }, SetOptions(merge: true));
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not save ${partner.id} logo: $error');
      return 'That did not go through. Try again.';
    }
  }

  /// The shop's payment QR, stored the same way its logo is. Null clears it.
  ///
  /// A separate field rather than a second logo because it is read on a
  /// completely different surface for a completely different reason: the mark
  /// identifies the shop on a card, and this is the thing a customer points
  /// their banking app at on the wizard's payment step. A shop with none simply
  /// has no code to show, which that step states in words — see
  /// [BrewShop.payQrBytes].
  ///
  /// Held to [maxLogoChars] rather than a ceiling of its own: a QR lives alone
  /// on the shop document beside a name, a description and a logo, so it has the
  /// same budget the logo does. It needs the resolution more than the logo does
  /// — a code that will not scan is a code that does not work — which is why the
  /// picker that feeds this downscales to 1024 rather than 512.
  Future<String?> setShopPayQrBase64(
    BrewPartner partner,
    Uint8List? bytes,
  ) async {
    if (bytes == null) {
      try {
        await _db.collection(_shops).doc(partner.id).set({
          'payQrBase64': null,
        }, SetOptions(merge: true));
        return null;
      } catch (error) {
        debugPrint('QuickBrew → could not clear ${partner.id} QR: $error');
        return 'That did not go through. Try again.';
      }
    }

    final encoded = base64Encode(bytes);
    if (encoded.length > maxLogoChars) {
      final kb = (encoded.length / 1024).round();
      return 'That image is too large at ${kb}KB. Pick a smaller one.';
    }

    try {
      await _db.collection(_shops).doc(partner.id).set({
        'payQrBase64': encoded,
      }, SetOptions(merge: true));
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not save ${partner.id} QR: $error');
      return 'That did not go through. Try again.';
    }
  }

  /// The three board writes, each returning null on success or the sentence to
  /// show — the same bargain [setUserStanding] and [setShopIdentity] strike.
  ///
  /// They used to hand back the raw Firestore future, which nothing on the store
  /// screen awaited or caught. That is the quietest failure in the app: an admin
  /// presses Save on a new item, the sheet closes as though it worked, the board
  /// below does not change, and the only trace is an unhandled async error in a
  /// log they are not reading. Adding an item that never arrived is exactly the
  /// case where saying nothing is worst — the next thing they do is press Add
  /// again.
  Future<String?> addMenuItem(
    BrewPartner partner, {
    required String name,
    String? description,
    String? category,
    String? subCategory,
    Map<BrewItemSize, int> sizePrices = const {},
    int? priceCents,
    double? sort,
    Uint8List? image,
  }) async {
    final (encodedImage, imageFailure) = _encodeItemImage(image);
    if (imageFailure != null) return imageFailure;

    try {
      await _db.collection(_shops).doc(partner.id).collection(_menu).add({
        'name': name,
        'description': description,
        'category': _tidy(category),
        'subCategory': _tidy(subCategory),
        'sizePrices': _encodeSizePrices(sizePrices),
        'priceCents': priceCents,
        'sort': sort,
        'imageBase64': encodedImage,
      });
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not add to ${partner.id}: $error');
      return 'That product did not save. Try again.';
    }
  }

  Future<String?> updateMenuItem(
    BrewPartner partner,
    String itemId, {
    required String name,
    String? description,
    String? category,
    String? subCategory,
    Map<BrewItemSize, int> sizePrices = const {},
    int? priceCents,
    double? sort,
    Uint8List? image,
  }) async {
    final (encodedImage, imageFailure) = _encodeItemImage(image);
    if (imageFailure != null) return imageFailure;

    try {
      await _db
          .collection(_shops)
          .doc(partner.id)
          .collection(_menu)
          .doc(itemId)
          .set({
            'name': name,
            'description': description,
            'category': _tidy(category),
            'subCategory': _tidy(subCategory),
            'sizePrices': _encodeSizePrices(sizePrices),
            'priceCents': priceCents,
            'sort': sort,
            'imageBase64': encodedImage,
          });
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not update $itemId: $error');
      return 'That product did not save. Try again.';
    }
  }

  /// An empty or whitespace-only field stored as null rather than as `''`,
  /// the same rule [setShopIdentity] applies to a cleared name: a category
  /// typed and then cleared should put the item back to uncategorised, not
  /// file it under a category whose name is the empty string — which
  /// [BrewMenuItem.categoriesOf] would then offer as a nameless filter chip.
  static String? _tidy(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Replaces a shop's whole board with [items], in one batch.
  ///
  /// This is a *replace*, not an append, and that is the only honest shape for
  /// it: run twice against a shop it would otherwise leave 232 drinks on a
  /// board that sells 116, with every one of them duplicated and no way to
  /// tell the copies apart. So every existing item goes in the same batch that
  /// writes the new ones — either the board ends up being exactly the supplied
  /// list, or, if the batch is refused, it is left exactly as it was. There is
  /// no window where the shop has half a menu.
  ///
  /// Firestore caps a batch at 500 operations. 116 items plus whatever is
  /// being cleared sits well inside that for this list, but the guard is here
  /// because the *next* list is not this one — a caller handing over 400 items
  /// against a board that already holds 200 would otherwise take an opaque
  /// server-side rejection instead of a sentence.
  ///
  /// Returns null on success, or the sentence to show.
  Future<String?> importMenu(
    BrewPartner partner,
    List<BrewSeedItem> items,
  ) async {
    if (items.isEmpty) return 'There was nothing in that list to import.';

    try {
      final collection =
          _db.collection(_shops).doc(partner.id).collection(_menu);
      final existing = await collection.get();

      final operations = existing.docs.length + items.length;
      if (operations > _batchLimit) {
        return 'That list is too long to import in one go '
            '($operations changes, $_batchLimit allowed).';
      }

      final batch = _db.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }
      for (final item in items) {
        batch.set(collection.doc(), {
          'name': item.name,
          'description': item.description,
          'category': _tidy(item.category),
          'subCategory': _tidy(item.subCategory),
          'sizePrices': _encodeSizePrices(item.sizePrices),
          'priceCents': item.priceCents,
          'sort': item.sort,
          // No pictures in the source list. Written as null rather than left
          // out so an item that had one before a re-import does not keep a
          // photo of a drink the new list may have renamed.
          'imageBase64': null,
        });
      }
      await batch.commit();
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not import into ${partner.id}: $error');
      return 'That import did not go through. Try again.';
    }
  }

  /// Firestore's own ceiling on a single batched write.
  static const _batchLimit = 500;

  /// Null rather than `{}` for an unsized item, matching every other
  /// optional field on this write — `set()` overwrites the whole document, so
  /// an item edited back down to no sizes has to actually clear the map
  /// rather than leave the old one behind.
  static Map<String, int>? _encodeSizePrices(Map<BrewItemSize, int> prices) =>
      prices.isEmpty
          ? null
          : {for (final entry in prices.entries) entry.key.storedValue: entry.value};

  /// The ceiling on an encoded item picture, in characters of base64. Same
  /// budget as [maxLogoChars] and the same reasoning: a downscaled picture at
  /// quality 75 lands far under it, and the limit exists so an oversized pick
  /// is refused with a sentence instead of rejected by the server with an
  /// INVALID_ARGUMENT nobody can act on.
  static const maxItemImageChars = 700 * 1024;

  /// Encodes an item's picture for storage, or names the sentence to show if
  /// it will not fit — the same check [setShopLogoBase64] makes for a shop's
  /// logo, pulled out here because both [addMenuItem] and [updateMenuItem]
  /// need it before they touch Firestore at all.
  (String? encoded, String? failure) _encodeItemImage(Uint8List? image) {
    if (image == null) return (null, null);
    final encoded = base64Encode(image);
    if (encoded.length > maxItemImageChars) {
      final kb = (encoded.length / 1024).round();
      return (null, 'That image is too large at ${kb}KB. Pick a smaller one.');
    }
    return (encoded, null);
  }

  Future<String?> deleteMenuItem(BrewPartner partner, String itemId) async {
    try {
      await _db
          .collection(_shops)
          .doc(partner.id)
          .collection(_menu)
          .doc(itemId)
          .delete();
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not delete $itemId: $error');
      return 'That product did not come off the board. Try again.';
    }
  }

  // --------------------------------------------------------------- add-ons
  //
  // The same four writes the board gets, against `shops/{shop}/addons`. Scoped
  // by partner exactly as the menu is, which is the whole of what makes one
  // shop's extras its own: there is no shared collection to leak out of.

  Future<String?> addAddOn(
    BrewPartner partner, {
    required String name,
    required int priceCents,
    String? group,
    double? sort,
  }) async {
    try {
      await _db.collection(_shops).doc(partner.id).collection(_addOns).add({
        'name': name,
        'priceCents': priceCents,
        'group': _tidy(group),
        'sort': sort,
      });
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not add an add-on to ${partner.id}: $error');
      return 'That add-on did not save. Try again.';
    }
  }

  Future<String?> updateAddOn(
    BrewPartner partner,
    String addOnId, {
    required String name,
    required int priceCents,
    String? group,
    double? sort,
  }) async {
    try {
      await _db
          .collection(_shops)
          .doc(partner.id)
          .collection(_addOns)
          .doc(addOnId)
          .set({
            'name': name,
            'priceCents': priceCents,
            'group': _tidy(group),
            'sort': sort,
          });
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not update add-on $addOnId: $error');
      return 'That add-on did not save. Try again.';
    }
  }

  Future<String?> deleteAddOn(BrewPartner partner, String addOnId) async {
    try {
      await _db
          .collection(_shops)
          .doc(partner.id)
          .collection(_addOns)
          .doc(addOnId)
          .delete();
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not delete add-on $addOnId: $error');
      return 'That add-on did not come off the list. Try again.';
    }
  }

  /// Replaces this shop's add-ons with [addOns], in one batch.
  ///
  /// A replace rather than an append, for the same reason [importMenu] is one:
  /// run twice it would otherwise leave the shop offering two of every extra
  /// with no way to tell the copies apart. Either the list ends up being
  /// exactly what was supplied, or — if the batch is refused — it is left
  /// exactly as it was.
  Future<String?> importAddOns(
    BrewPartner partner,
    List<BrewSeedAddOn> addOns,
  ) async {
    if (addOns.isEmpty) return 'There was nothing in that list to import.';

    try {
      final collection =
          _db.collection(_shops).doc(partner.id).collection(_addOns);
      final existing = await collection.get();

      final operations = existing.docs.length + addOns.length;
      if (operations > _batchLimit) {
        return 'That list is too long to import in one go '
            '($operations changes, $_batchLimit allowed).';
      }

      final batch = _db.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }
      for (final addOn in addOns) {
        batch.set(collection.doc(), {
          'name': addOn.name,
          'priceCents': addOn.priceCents,
          'group': _tidy(addOn.group),
          'sort': addOn.sort,
        });
      }
      await batch.commit();
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not import add-ons into ${partner.id}: $error');
      return 'That import did not go through. Try again.';
    }
  }

  /// Takes every add-on off this shop's list, in one batch.
  ///
  /// Offered because the alternative for a shop that has stopped selling
  /// extras is deleting twenty rows one at a time, each with its own
  /// confirmation.
  Future<String?> clearAddOns(BrewPartner partner) async {
    try {
      final collection =
          _db.collection(_shops).doc(partner.id).collection(_addOns);
      final existing = await collection.get();
      if (existing.docs.isEmpty) return null;

      if (existing.docs.length > _batchLimit) {
        return 'There are too many add-ons to clear in one go '
            '(${existing.docs.length}, $_batchLimit allowed).';
      }

      final batch = _db.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not clear ${partner.id} add-ons: $error');
      return 'That did not go through. Try again.';
    }
  }

  // ---------------------------------------------------------------- orders
  //
  // The counter's own queue: every order this shop has taken, and the one
  // write that moves one along. Customers place orders through
  // BrewCounter.placeOrder; nothing here creates or deletes one — an order
  // that exists is a promise already made, and this shop's only say in it is
  // how far along it is.

  /// Every order filed under [partner], oldest first.
  ///
  /// Oldest first rather than [BrewCounter]'s newest-first: that stream serves
  /// a customer's own history, where the order they just placed is what they
  /// came to see. This one serves a queue at a counter, where the order that
  /// has been waiting longest is the one to make next — the same reading a
  /// physical ticket rail gives.
  Stream<List<BrewOrder>> ordersFor(BrewPartner partner) {
    return _db
        .collection(_orders)
        .where('shop', isEqualTo: partner.id)
        .snapshots()
        .map((snapshot) {
          final orders = [
            for (final doc in snapshot.docs) ?BrewOrder.read(doc.id, doc.data()),
          ];
          orders.sort(_oldestFirst);
          return orders;
        })
        .handleError((Object error) {
          debugPrint('QuickBrew → ${partner.id} orders unavailable: $error');
          throw error;
        });
  }

  /// Ascending by `placedAt`, with an unstamped order counted as the oldest
  /// thing there is — the reverse of [BrewCounter._newestFirst], and for the
  /// reverse reason: a queue that let a just-placed, not-yet-stamped order
  /// jump to the back of the line would make the counter wait on it twice.
  static int _oldestFirst(BrewOrder a, BrewOrder b) {
    final (left, right) = (a.placedAt, b.placedAt);
    if (left == null && right == null) return 0;
    if (left == null) return -1;
    if (right == null) return 1;
    return left.compareTo(right);
  }

  /// Moves one order to [next], and touches nothing else on it.
  ///
  /// There is deliberately no method that sets a stage outright: the only
  /// thing a counter screen ever needs is "the next one", and taking a whole
  /// [BrewOrderStage] here would let a caller skip a stage or move one
  /// backward by mistake. [BrewOrderStage.next] is what the screen reads to
  /// find the value to pass, and it returns null once an order is already
  /// [BrewOrderStage.completed] — there is nothing further to advance to.
  ///
  /// Returns null on success, or the sentence to show — the same bargain
  /// every other write on this layer strikes.
  ///
  /// [update]'s future only completes once the server acknowledges the
  /// write, not once it is queued locally, so a shop with no route to
  /// Firestore — offline, or a firewall between it and Google — would
  /// otherwise leave the button that called this reading "Saving" forever.
  /// [_writeTimeout] turns that silent hang into the same sentence any other
  /// refused write already shows.
  Future<String?> advanceOrderStage(String orderId, BrewOrderStage next) async {
    try {
      await _db.collection(_orders).doc(orderId).update({
        'stage': next.name,
      }).timeout(_writeTimeout);
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not advance order $orderId: $error');
      return 'That did not go through. Try again.';
    }
  }

  /// Declines one order outright — the one jump [advanceOrderStage] does not
  /// offer, from whichever active stage the order was sitting in straight to
  /// [BrewOrderStage.rejected].
  ///
  /// [reason] is the shop's own words for why — out of stock, closing early —
  /// shown back to whoever is looking at the order later. Optional: a shop
  /// that just wants the order off its queue is not made to type something
  /// first. Trimmed and stored as null rather than as `''` when left blank,
  /// the same rule [setShopIdentity] applies to a cleared name.
  ///
  /// Returns null on success, or the sentence to show — the same bargain
  /// every other write on this layer strikes, and the same [_writeTimeout]
  /// reasoning [advanceOrderStage] gives.
  Future<String?> rejectOrder(String orderId, {String? reason}) async {
    final trimmed = reason?.trim();
    try {
      await _db.collection(_orders).doc(orderId).update({
        'stage': BrewOrderStage.rejected.name,
        'rejectionReason': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      }).timeout(_writeTimeout);
      return null;
    } catch (error) {
      debugPrint('QuickBrew → could not reject order $orderId: $error');
      return 'That did not go through. Try again.';
    }
  }

  /// How long [advanceOrderStage] and [rejectOrder] wait on Firestore's own
  /// acknowledgement before giving up and reporting the write as failed.
  /// Generous enough that an ordinary slow connection still succeeds, short
  /// enough that a shop with no route to Firestore at all is told so well
  /// before anyone at the counter would call it frozen.
  static const _writeTimeout = Duration(seconds: 15);
}
