import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brew_admin.dart';
import 'brew_auth.dart';
import 'brew_counter.dart';
import 'brew_flow.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/create_account_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/maintenance_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/order_wizard_screen.dart';
import 'services/system_maintenance.dart';
import 'theme/brew_type.dart';
import 'theme/tokens.dart';
import 'widgets/brew_background.dart';

/// The three halves of the backend, or the nulls that stand in for them.
///
/// Firestore is only attempted if Firebase itself came up: [BrewCounter.connect]
/// and [BrewAdmin.connect] read `FirebaseFirestore.instance`, and asking for it
/// with no app initialised throws rather than returning the null that means
/// "not available here".
typedef BrewBackend = ({BrewAuth? auth, BrewCounter? counter, BrewAdmin? admin});

Future<BrewBackend> connectBrew() async {
  final auth = await BrewAuth.connect();
  return (
    auth: auth,
    counter: auth == null ? null : BrewCounter.connect(),
    admin: auth == null ? null : BrewAdmin.connect(),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The field is the dominant background, so it should run under the system
  // bars rather than stopping at them. Android 15+ enforces this for
  // targetSdk 35+ anyway; the call is what makes it behave the same way on
  // Android 10-14, where `systemNavigationBarColor` would otherwise paint an
  // opaque bar instead of letting the field through.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Started here and deliberately not awaited. The splash owes Firebase nothing,
  // and awaiting it before `runApp` would hold the reader on the Android launch
  // theme for however long the native SDK takes. The 2.4s extraction is more
  // than enough cover: a restored session is read off disk in milliseconds, so
  // by the time the cup has finished filling the app already knows whether it is
  // opening on the landing screen or on somebody's home screen.
  runApp(QuickBrewApp(backend: connectBrew()));
}

class QuickBrewApp extends StatefulWidget {
  const QuickBrewApp({super.key, this.backend});

  /// The account and counter layers, still connecting. Null — and so is what it
  /// resolves to — in tests and on any build without Firebase configuration; the
  /// forms then report that rather than the app failing to start.
  final Future<BrewBackend>? backend;

  @override
  State<QuickBrewApp> createState() => _QuickBrewAppState();
}

/// The whole map of the app is this one rule: **a session means home.**
///
/// Nothing else routes. Logging in does not navigate, signing up does not
/// navigate, and neither form knows what a successful submit leads to — they
/// report their own failures and stop. What moves the reader is
/// [BrewAuth.sessions] emitting a user, whether that came from a form they just
/// filled in or from a session Firebase restored off disk at launch. Which means
/// there is exactly one place that can be wrong about who is signed in.
class _QuickBrewAppState extends State<QuickBrewApp> {
  /// Needed because the thing that decides to navigate is a stream listener, not
  /// a widget with a context under the Navigator.
  final _navigator = GlobalKey<NavigatorState>();

  BrewAuth? _auth;
  BrewCounter? _counter;
  BrewAdmin? _admin;
  BrewSession? _session;

  /// What `users/{uid}` says the signed-in account may configure. Null before
  /// [BrewAdmin.ensureProfile] has finished writing it — briefly, on a first
  /// sign-in — and for the whole session if Firestore is unreachable. Either
  /// way the reader lands on [HomeScreen] rather than stalling: a role that
  /// cannot be read is the same, from here, as not having one.
  BrewUserProfile? _profile;

  StreamSubscription<BrewSession?>? _watch;
  StreamSubscription<BrewUserProfile?>? _profileWatch;
  StreamSubscription<SystemMaintenanceStatus>? _maintenanceWatch;
  SystemMaintenanceStatus _maintenance = SystemMaintenanceStatus.normal;

  /// Held open for the life of the app, and it throws every snapshot away.
  ///
  /// Its whole purpose is that *somebody* is listening to the shops from the
  /// moment Firestore connects, which is during the splash — and the same 2.4s
  /// of extraction that covers restoring a session covers two documents landing
  /// too. Without it the first screen to mount is also the first subscriber, so
  /// it pays that round trip in front of the reader with the enum's built-in
  /// "Drip & Co" and "Seven Coffee & Tea" on screen, and every login is followed
  /// by both cards visibly renaming themselves. See [BrewCounter.lastShops],
  /// which is where what this receives actually lands.
  ///
  /// One listener, not one per screen: Firestore keeps a single watch per query,
  /// so the screens' own subscriptions ride the same stream this opened rather
  /// than each fetching the collection again.
  StreamSubscription<List<BrewShop>>? _shopsWarm;

  /// Whether the profile stream has answered for the current session yet —
  /// including answering "there is no document", which is a real answer.
  ///
  /// This is not the same question as `_profile != null`, and the difference is
  /// a screen. A null profile means *either* "still asking" or "asked, and this
  /// account configures nothing", and routing on it alone sends every admin
  /// through a flash of the customer home screen on their way to the dashboard
  /// — cards, greeting and all — because that is what null resolves to while the
  /// read is in flight.
  bool _profileResolved = false;

  /// How long home will wait for the profile before giving up and rendering the
  /// customer screen.
  ///
  /// The wait needs a floor under it, not just a stream: [BrewAdmin.profile]
  /// swallows its own errors rather than emitting them, so a refused read — the
  /// rules not deployed, say — is indistinguishable from a slow one and would
  /// otherwise hold the reader on a blank field forever. When this fires the app
  /// does exactly what it did before any of this existed: treats an unreadable
  /// role as no role, and shows the customer app.
  static const _profileWait = Duration(milliseconds: 1200);
  Timer? _profileDeadline;

  /// The splash has run and handed the cup over.
  ///
  /// Gating home on this is what stops a returning reader's session — which
  /// arrives a few hundred milliseconds in — from cutting the extraction off
  /// mid-pour. It also doubles as "the splash has already been spent this run",
  /// which is what makes logging out land on the landing screen instead of
  /// replaying the brand animation.
  bool _splashSpent = false;

  bool get _showHome => _session != null && _splashSpent;

  @override
  void initState() {
    super.initState();
    widget.backend?.then(_onConnected);
  }

  @override
  void dispose() {
    _watch?.cancel();
    _profileWatch?.cancel();
    _maintenanceWatch?.cancel();
    _shopsWarm?.cancel();
    _profileDeadline?.cancel();
    super.dispose();
  }

  void _onConnected(BrewBackend backend) {
    if (!mounted) return;
    final auth = backend.auth;

    final was = _showHome;
    setState(() {
      _auth = auth;
      _counter = backend.counter;
      _admin = backend.admin;
      // Read synchronously as well as subscribed, so the first build after
      // connecting already knows. `userChanges` does emit the restored user, but
      // on the next microtask — and that is one frame in which a signed-in reader
      // would be on their way to the landing screen.
      _session = auth?.current;
    });
    if (_showHome != was) _clearStack();
    _syncProfile(_session);

    // Watch real-time maintenance status broadcast from Website Admin console
    _maintenanceWatch?.cancel();
    _maintenanceWatch = watchSystemMaintenance().listen((status) {
      if (!mounted) return;
      final wasActive = _maintenance.isActive;
      setState(() => _maintenance = status);
      if (status.isActive &&
          !wasActive &&
          !(_profile?.role.canConfigureStores ?? false)) {
        _clearStack();
      }
    });

    // Started here rather than lazily on the first screen that wants it — the
    // point is the head start. See [_shopsWarm].
    _shopsWarm = backend.counter?.shops().listen((_) {});

    _watch = auth?.sessions.listen(_onSession);
  }

  void _onSession(BrewSession? session) {
    if (!mounted) return;
    final was = _showHome;
    setState(() => _session = session);
    if (_showHome != was) _clearStack();
    _syncProfile(session);
  }

  /// Keeps [_profile] pointed at whoever [_session] now is.
  ///
  /// Called on every session change, not only sign-up: an admin invited last
  /// week is still a customer as far as their own device remembers until they
  /// next sign in, which is the log-in [BrewAdmin.ensureProfile] has to run
  /// on too. Re-subscribing rather than reusing the previous stream is what
  /// stops one account's profile briefly answering for the next one's uid
  /// when a reader signs out and a different reader signs in on the same
  /// device.
  void _syncProfile(BrewSession? session) {
    _profileWatch?.cancel();
    _profileWatch = null;
    _profileDeadline?.cancel();
    _profileDeadline = null;

    final admin = _admin;
    if (session == null || admin == null) {
      setState(() {
        _profile = null;
        // Nothing is going to answer, so nothing is waiting on an answer. A
        // build with no Firestore behind it must not hold anybody on a blank
        // field — it goes straight to the customer app, as it always has.
        _profileResolved = true;
      });
      return;
    }

    setState(() {
      _profile = null;
      _profileResolved = false;
    });
    _profileDeadline = Timer(_profileWait, () {
      if (mounted) setState(() => _profileResolved = true);
    });

    // Deliberately not awaited — this is called from a stream listener and
    // from a `then`, neither of which can wait — but every failure inside is
    // caught and logged there rather than thrown, so nothing escapes into an
    // unhandled async error. The `catchError` is the belt to that braces: an
    // unawaited future that somehow still throws would otherwise take out the
    // frame that happens to be building when it lands.
    admin
        .ensureProfile(
          uid: session.uid,
          email: session.email ?? '',
          name: session.name,
        )
        .catchError((Object error) {
          debugPrint('QuickBrew → profile setup failed: $error');
        });

    // The subscription is attached regardless of whether the write above
    // succeeds: a profile written on a previous launch, or by hand in the
    // console, is still there to be read.
    _profileWatch = admin.profile(session.uid).listen(
      (profile) {
        if (!mounted) return;
        setState(() {
          _profile = profile;
          // The first emission is the answer, whatever it says. A null here is
          // "this account has no profile document", which routes to the customer
          // app on purpose — unlike the null it was initialised to.
          _profileResolved = true;
        });
      },
      onError: (Object error) {
        // The stream already logs and swallows; this is here so a failure that
        // reaches the subscription cannot become an unhandled error either.
        debugPrint('QuickBrew → profile stream failed: $error');
      },
      // A stream that ends without ever emitting has answered as definitively as
      // one that emitted — Firestore closes the watch on a refused read — so the
      // reader is let through now rather than made to wait out [_profileWait].
      onDone: () {
        if (mounted) setState(() => _profileResolved = true);
      },
    );
  }

  /// Fired by the flow once the cup is down.
  void _onLanded() {
    if (_splashSpent || !mounted) return;
    final was = _showHome;
    setState(() => _splashSpent = true);
    if (_showHome != was) _clearStack();
  }

  /// Drops everything pushed on top of the root.
  ///
  /// Swapping what the root route builds is what changes the screen; this is what
  /// gets the login form — or the menu the reader was reading when they logged
  /// out — out of the way of it. Deferred a frame because the setState that
  /// preceded it has not been laid out yet, and popping inside the same build
  /// would run a route transition against a tree mid-rebuild.
  void _clearStack() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickBrew',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: BrewColor.field,
        colorScheme: const ColorScheme.dark(
          surface: BrewColor.field,
          onSurface: BrewColor.cream,
          primary: BrewColor.cream,
          onPrimary: BrewColor.field,
          secondary: BrewColor.sage,
          onSecondary: BrewColor.cream,
        ),
        textTheme: const TextTheme(
          displayLarge: BrewType.display,
          titleMedium: BrewType.title,
          bodyMedium: BrewType.body,
          labelSmall: BrewType.mono,
        ),
      ),
      // A button's name survives the whole flow: Log in goes to a screen whose
      // primary action is also Log in. Never Submit, never Continue.
      home: Scaffold(
        // Builder, so the callbacks below close over a context that has the
        // MaterialApp's Navigator above it rather than this widget's, which
        // does not.
        body: Builder(builder: _root),
      ),
    );
  }

  Widget _root(BuildContext context) {
    final session = _session;
    final isAdmin = _profile != null && _profile!.role.canConfigureStores;

    // Mobile app maintenance lockout:
    // When enabled via the Website Admin Portal, locks regular customers out
    // of browsing or placing orders. Admins retain dashboard access to manage stores.
    if (_maintenance.isActive && !isAdmin) {
      if (session != null && !_profileResolved) {
        return const BrewBackground(child: SizedBox.expand());
      }
      return MaintenanceScreen(
        message: _maintenance.message,
        onRefresh: () async {
          if (mounted) setState(() {});
        },
        onAdminBypass: () => _openLogin(context),
      );
    }

    if (_showHome && session != null) {
      // Signed in, and which home is still an open question. Held on the field
      // colour for the moment that takes — a bare continuation of the screen the
      // login form was drawn on — rather than answering it wrongly and
      // correcting itself: an admin who watched the customer home screen build
      // itself, cards and greeting and all, before being replaced by the
      // dashboard would reasonably read that as the app not knowing who they
      // are. Bounded by [_profileWait], so this is never where anybody stays.
      if (!_profileResolved) {
        return const BrewBackground(child: SizedBox.expand());
      }

      final profile = _profile;
      if (profile != null && profile.role.canConfigureStores) {
        return AdminHomeScreen(
          profile: profile,
          admin: _admin,
          counter: _counter,
          onSignOut: _signOut,
        );
      }
      return HomeScreen(
        session: session,
        counter: _counter,
        onViewMenu: (shop) => _openMenu(context, shop),
        onResumeDraft: (draft) => _resumeDraft(context, draft),
        onDiscardDraft: (draft) => _discardDraft(session),
        onSignOut: _signOut,
      );
    }

    return BrewFlow(
      // True on every build after the first landing, and read only once when a
      // BrewFlow is mounted — so it is false for the launch splash and true for
      // the fresh flow that logging out puts back at the root.
      startLanded: _splashSpent,
      onLanded: _onLanded,
      onGetStarted: () => _openLogin(context),
      onCreateAccount: () => _openCreateAccount(context),
    );
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      LoginScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        onSubmit: _logIn,
        onResetPassword: _sendPasswordReset,
        onCreateAccount: () => _openCreateAccount(context),
      ),
    );
  }

  /// Pushed on top of login rather than replacing it, so Back and "I already
  /// have an account" both land the reader back on the form they came from with
  /// whatever they had typed still in it.
  void _openCreateAccount(BuildContext context) {
    Navigator.of(context).push(
      CreateAccountScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        onSubmit: _createAccount,
        onLogIn: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  /// The session goes with the shop because the board's Buy leads into the
  /// order wizard, and an order is filed under a uid. Read here rather than
  /// passed in by the home screen for the same reason [_counter] is: this is
  /// where both live, and a callback that had to carry them would be the home
  /// screen holding state on the wizard's behalf.
  void _openMenu(BuildContext context, BrewShop shop) {
    Navigator.of(context).push(
      MenuScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        shop: shop,
        session: _session,
        counter: _counter,
      ),
    );
  }

  /// Reopens the wizard on the order the reader saved.
  ///
  /// The wizard needs a [BrewMenuItem] to open on and the draft carries item
  /// *ids*, so the board is read once here before the push. Resolved from the
  /// same [BrewCounter.menu] stream the wizard itself then subscribes to for its
  /// lines — Firestore keeps one watch per query, so this is the same read, not a
  /// second one.
  ///
  /// The shop goes with it for its live name, resolved from [BrewCounter.lastShops]
  /// the same way the home screen's own card resolves it. A draft naming a shop
  /// whose board no longer has any of its items opens on step one of a fresh
  /// order for that shop rather than refusing: the reader asked to carry on
  /// ordering, and the wizard's own [BrewDraft] handling is what tells them what
  /// could not be recovered.
  Future<void> _resumeDraft(BuildContext context, BrewDraft draft) async {
    final counter = _counter;
    if (counter == null) return;

    final reduced = MediaQuery.disableAnimationsOf(context);
    final navigator = Navigator.of(context);

    final menu = await counter.menu(draft.partner).first;
    if (!mounted) return;

    // The first line's item is what step one opens on, and what the wizard falls
    // back to if its own restore recovers nothing. Any item from the board will
    // do when that line's own item has gone — the reader is being put back on a
    // picker either way.
    final wanted = draft.lines.first.itemId;
    final item = menu.where((item) => item.id == wanted).firstOrNull ??
        menu.firstOrNull;
    if (item == null) {
      // An empty board is nothing to resume into. The draft is left alone rather
      // than discarded: the shop's menu being briefly unreadable is not the
      // reader's order being wrong.
      debugPrint('QuickBrew → cannot resume, ${draft.partner.id} menu is empty');
      return;
    }

    final shops = counter.lastShops;
    final shop = shops
            ?.where((shop) => shop.partner == draft.partner)
            .firstOrNull ??
        BrewShop(partner: draft.partner, status: BrewShopStatus.unknown);

    navigator.push(
      OrderWizardScreen.route(
        reduced: reduced,
        shop: shop,
        item: item,
        session: _session,
        counter: counter,
        draft: draft,
      ),
    );
  }

  /// Throws the saved order away. The card goes with it, because the home
  /// screen's draft stream is what draws the card.
  void _discardDraft(BrewSession session) {
    // Not awaited and nothing to report: [BrewCounter.discardDraft] swallows its
    // own failures, and a delete that did not land leaves the card exactly where
    // it was — a state the reader can see and press again.
    _counter?.discardDraft(session.uid);
  }

  /// Clears in-memory user state before the auth session is torn down.
  Future<void> _signOut() async {
    _profileWatch?.cancel();
    _profileWatch = null;
    _profileDeadline?.cancel();
    _profileDeadline = null;
    _counter?.clearCache();

    final was = _showHome;
    if (mounted) {
      setState(() {
        _session = null;
        _profile = null;
        _profileResolved = true;
      });
    }
    if (_showHome != was) _clearStack();

    try {
      await _auth?.signOut();
    } catch (error) {
      debugPrint('QuickBrew → sign-out failed: $error');
    }
  }

  /// Firebase Auth signs the account in. Returns the failure for the form to
  /// display, or null — at which point [_onSession] has the reader on their way
  /// to home, which is why nothing here navigates.
  Future<BrewAuthFailure?> _logIn(String email, String password) async {
    final auth = _auth;
    if (auth == null) return _notConnected;
    return auth.signIn(email: email, password: password);
  }

  /// Dispatches a password reset email through Firebase Auth.
  Future<BrewAuthFailure?> _sendPasswordReset(String email) async {
    final auth = _auth;
    if (auth == null) return _notConnected;
    return auth.sendPasswordResetEmail(email: email);
  }

  /// The real thing: Firebase Auth creates the account and leaves the reader
  /// signed in.
  Future<BrewAuthFailure?> _createAccount(
    String name,
    String email,
    String password,
  ) async {
    final auth = _auth;
    if (auth == null) return _notConnected;

    final failure = await auth.createAccount(
      name: name,
      email: email,
      password: password,
    );
    if (failure == null) debugPrint('QuickBrew → signed up $name <$email>');
    return failure;
  }

  /// No Firebase to talk to. Said on the form rather than swallowed, because a
  /// button that quietly does nothing is the worst of the available behaviours.
  static const _notConnected = BrewAuthFailure(
    BrewAuthField.form,
    'Accounts are not connected in this build.',
  );
}
