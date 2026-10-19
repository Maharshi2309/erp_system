import '../../../core/errors/failure.dart';
import '../domain/settings.dart';

/// DEMO ONLY — organization settings in memory.
class DemoSettingsRepository implements SettingsRepository {
  DemoSettingsRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  final _orgs = <String, OrgSettings>{};

  Future<void> _delay() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  @override
  Future<OrgSettings> load(String organizationId) async {
    await _delay();
    return _orgs[organizationId] ?? const OrgSettings();
  }

  @override
  Future<OrgSettings> save(String organizationId, OrgSettings settings) async {
    await _delay();
    final errors = validateSecurity(settings.security);
    if (errors.isNotEmpty) {
      throw ValidationFailure(errors.values.first, fieldErrors: errors);
    }
    return _orgs[organizationId] = settings;
  }

  /// Read without waiting (sign-in checks the two-step policy).
  OrgSettings peek(String organizationId) =>
      _orgs[organizationId] ?? const OrgSettings();
}
