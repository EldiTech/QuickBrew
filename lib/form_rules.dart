/// The checks the login and create-account forms share.
///
/// Factored out because both screens ask for the same email and the same
/// password, and two copies of the rule are two copies that drift — the wording
/// of a rejection is part of the rule, not decoration on top of it.
///
/// All of this is local shape-checking only. None of it says an account exists,
/// which is the server's job and the server's message.
abstract final class BrewRules {
  /// Deliberately permissive: one @, something either side, a dot in the
  /// domain. Anything stricter starts rejecting addresses that are valid, and
  /// this check cannot confirm one exists anyway — so being strict buys nothing
  /// and costs real users.
  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Not a policy — the floor below which the field is obviously unfinished.
  /// Stated to the user up front on the create-account form rather than sprung
  /// on them after they submit.
  static const minPassword = 8;

  /// [ifEmpty] is the caller's, because "enter the email you signed up with"
  /// and "enter an email" are different sentences on the two screens even
  /// though the rule behind them is the same.
  static String? email(String value, {required String ifEmpty}) => switch (value) {
    '' => ifEmpty,
    _ when !_emailShape.hasMatch(value) =>
      'That address is missing a @ or a domain.',
    _ => null,
  };

  static String? password(String value, {required String ifEmpty}) =>
      switch (value) {
        '' => ifEmpty,
        _ when value.length < minPassword =>
          'Passwords are at least $minPassword characters.',
        _ => null,
      };

  /// Trimmed before it gets here. Only length is checkable: names are not
  /// something to validate the shape of.
  static String? name(String value) => switch (value) {
    '' => 'Tell us what to call you.',
    _ when value.length < 2 => 'That is too short to call out.',
    _ => null,
  };
}
