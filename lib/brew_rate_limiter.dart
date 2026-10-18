/// Slows down repeated rejected attempts at a form, on this device.
///
/// Firebase keeps its own limit on the server and answers `too-many-requests`
/// when it trips, but that limit is generous, is not the same for every
/// project, and cannot be seen from the form until it has already been hit.
/// This one is ours, so its rules can be stated: [maxFailures] rejections
/// inside [window] lock the form for [baseLockout], and each lockout after
/// that doubles, up to [maxLockout]. Getting in clears the slate.
///
/// It is a client-side guard and makes no claim to be more than that: it stops
/// someone at the counter cycling through passwords on a phone, and it stops
/// the app itself from hammering Auth. Anyone calling Firebase directly is
/// Firebase's limit's problem.
///
/// Held in memory only. [BrewAuth] is made once per launch, so the count lasts
/// as long as the app does; a restart clears it, which is the right trade for a
/// guard that would otherwise lock a reader out of their own phone across days.
class BrewRateLimiter {
  BrewRateLimiter({
    this.maxFailures = 5,
    this.window = const Duration(minutes: 15),
    this.baseLockout = const Duration(seconds: 30),
    this.maxLockout = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final int maxFailures;

  /// How far back a rejection still counts. A failure older than this is
  /// forgotten, and so is the lockout streak if nothing has failed since.
  final Duration window;

  final Duration baseLockout;
  final Duration maxLockout;

  final DateTime Function() _now;
  final Map<String, _Record> _records = {};

  /// How long [key] must still wait, or null if it may try now.
  Duration? retryAfter(String key) {
    final record = _records[key];
    final until = record?.lockedUntil;
    if (until == null) return null;

    final remaining = until.difference(_now());
    if (remaining > Duration.zero) return remaining;

    record!.lockedUntil = null;
    return null;
  }

  /// Counts a rejected attempt against [key], locking it if that was one too
  /// many.
  void recordFailure(String key) {
    final now = _now();
    final record = _records.putIfAbsent(key, _Record.new);

    record.failures.removeWhere((at) => now.difference(at) > window);
    final last = record.lastFailure;
    if (last != null && now.difference(last) > window) record.strikes = 0;

    record.failures.add(now);
    record.lastFailure = now;

    if (record.failures.length >= maxFailures) {
      // Clamped so a long streak cannot overflow the shift; past ten doublings
      // the cap has long since won anyway.
      final lockout = baseLockout * (1 << record.strikes.clamp(0, 10));
      record.lockedUntil = now.add(lockout > maxLockout ? maxLockout : lockout);
      record.strikes += 1;
      record.failures.clear();
    }
  }

  /// The attempt went through: whatever [key] had against it is gone.
  void recordSuccess(String key) => _records.remove(key);
}

class _Record {
  final List<DateTime> failures = [];
  DateTime? lastFailure;
  DateTime? lockedUntil;

  /// Lockouts served in a row, which is what the next one doubles from.
  int strikes = 0;
}
