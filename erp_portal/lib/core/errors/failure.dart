/// Typed failures that repositories throw and providers expose through
/// `AsyncValue.error`. Widgets show [message]; they never parse exceptions.
sealed class Failure implements Exception {
  const Failure(this.message);

  /// Plain-language text that is safe to show to the user.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server could not be reached. Nothing was saved.
final class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message =
        'We couldn’t reach the server. Nothing was changed — try again.',
  ]);
}

/// Input rejected. [fieldErrors] maps a field key to its inline message.
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.fieldErrors = const {}});

  final Map<String, String> fieldErrors;
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure([
    super.message = 'This record doesn’t exist or was moved.',
  ]);
}

/// The member is not allowed to perform the operation.
final class PermissionFailure extends Failure {
  const PermissionFailure([
    super.message = 'You don’t have access to do this.',
  ]);
}

/// Someone else changed the record first; nothing was overwritten.
final class ConflictFailure extends Failure {
  const ConflictFailure([
    super.message =
        'Someone else changed this first. Your edits weren’t saved, so nothing was overwritten.',
  ]);
}

/// Too many attempts; the action is paused until [until].
final class LockedFailure extends Failure {
  const LockedFailure(super.message, {required this.until});

  final DateTime until;
}

/// A link or code that worked once has expired or was already used.
final class ExpiredFailure extends Failure {
  const ExpiredFailure(super.message);
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure([
    super.message = 'Something went wrong. Try again.',
    this.reference,
  ]);

  /// Support reference shown with the error, e.g. `req_8a234`.
  final String? reference;
}

/// Turns any error into user-facing text without leaking internals.
String userMessageFor(Object error) =>
    error is Failure ? error.message : const UnexpectedFailure().message;
