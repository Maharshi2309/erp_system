import 'package:flutter/foundation.dart';

/// "How many people work here?" options (board S13).
const employeeRanges = [
  '1–10',
  '11–50',
  '51–200',
  '201–500',
  '501–1,000',
  '1,000+',
];

const defaultTimeZone = 'Asia/Kolkata';

/// IANA time zones offered in selects. India first (D-03); others for
/// branches abroad. Stored as the IANA id, never a fixed offset (PRD §5.1).
const commonTimeZones = <(String, String)>[
  ('Asia/Kolkata', 'Asia/Kolkata (India, UTC+05:30)'),
  ('Asia/Dubai', 'Asia/Dubai (UTC+04:00)'),
  ('Asia/Karachi', 'Asia/Karachi (UTC+05:00)'),
  ('Asia/Kathmandu', 'Asia/Kathmandu (UTC+05:45)'),
  ('Asia/Dhaka', 'Asia/Dhaka (UTC+06:00)'),
  ('Asia/Colombo', 'Asia/Colombo (UTC+05:30)'),
  ('Asia/Singapore', 'Asia/Singapore (UTC+08:00)'),
  ('Asia/Tokyo', 'Asia/Tokyo (UTC+09:00)'),
  ('Europe/London', 'Europe/London (UTC+00:00 / +01:00)'),
  ('Europe/Berlin', 'Europe/Berlin (UTC+01:00 / +02:00)'),
  ('Africa/Nairobi', 'Africa/Nairobi (UTC+03:00)'),
  ('America/New_York', 'America/New_York (UTC−05:00 / −04:00)'),
  ('America/Los_Angeles', 'America/Los_Angeles (UTC−08:00 / −07:00)'),
  ('Australia/Sydney', 'Australia/Sydney (UTC+10:00 / +11:00)'),
];

String timeZoneLabel(String id) =>
    commonTimeZones.where((z) => z.$1 == id).map((z) => z.$2).firstOrNull ?? id;

@immutable
class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.employeeRange,
    this.logo,
    this.legalName = '',
    this.industry = '',
    this.registrationNumber = '',
    this.contactEmail = '',
    this.contactPhone = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.pin = '',
    this.country = 'India',
    this.timeZone = defaultTimeZone,
    this.createdAt,
    this.updatedAt,
    this.updatedBy = '',
  });

  /// Also used in sign-in links; can't change (board S35).
  final String id;
  final String name;
  final String employeeRange;
  final Uint8List? logo;
  final String legalName;
  final String industry;
  final String registrationNumber;
  final String contactEmail;
  final String contactPhone;
  final String address;
  final String city;
  final String state;
  final String pin;
  final String country;

  /// IANA id. Branches inherit it unless they set their own (Q-07).
  final String timeZone;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String updatedBy;

  Organization copyWith({
    String? name,
    String? employeeRange,
    Uint8List? logo,
    bool clearLogo = false,
    String? legalName,
    String? industry,
    String? registrationNumber,
    String? contactEmail,
    String? contactPhone,
    String? address,
    String? city,
    String? state,
    String? pin,
    String? country,
    String? timeZone,
    DateTime? updatedAt,
    String? updatedBy,
  }) => Organization(
    id: id,
    name: name ?? this.name,
    employeeRange: employeeRange ?? this.employeeRange,
    logo: clearLogo ? null : (logo ?? this.logo),
    legalName: legalName ?? this.legalName,
    industry: industry ?? this.industry,
    registrationNumber: registrationNumber ?? this.registrationNumber,
    contactEmail: contactEmail ?? this.contactEmail,
    contactPhone: contactPhone ?? this.contactPhone,
    address: address ?? this.address,
    city: city ?? this.city,
    state: state ?? this.state,
    pin: pin ?? this.pin,
    country: country ?? this.country,
    timeZone: timeZone ?? this.timeZone,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );
}

/// The owner's own profile, separate from employee records (board S16).
@immutable
class OwnerProfile {
  const OwnerProfile({
    required this.fullName,
    required this.email,
    this.phone = '',
    this.designation = '',
    this.photo,
  });

  final String fullName;
  final String email;
  final String phone;
  final String designation;
  final Uint8List? photo;
}

/// Where the owner last was in setup, for "Continue where you left off".
@immutable
class SetupBookmark {
  const SetupBookmark({required this.branchId, required this.step});

  final String branchId;
  final String step;
}
