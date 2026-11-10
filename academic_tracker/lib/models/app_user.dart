/// A profile field the user must fill in before using the app.
enum ProfileField { fullName, email, studentClass }

/// A user's `profile/info` document.
///
/// [uid] is the Firebase Auth UID. It is the document ID rather than a stored
/// field, so a user can only ever have one profile document.
class AppUser {
  const AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    this.studentClass,
    this.subjects = const [],
  });

  final String uid;
  final String fullName;
  final String email;

  /// Stored as `class`, which is a reserved word in Dart. Holds a label such as
  /// "Class 10" or "Year 2", or null when the user has not chosen one.
  final String? studentClass;
  final List<String> subjects;

  /// Required fields that are empty. Subjects are optional: a new user has
  /// none until they add some.
  List<ProfileField> get missingFields => [
    if (fullName.trim().isEmpty) ProfileField.fullName,
    if (email.trim().isEmpty) ProfileField.email,
    if ((studentClass ?? '').trim().isEmpty) ProfileField.studentClass,
  ];

  Map<String, dynamic> toMap() => {
    'fullName': fullName,
    'email': email,
    'class': studentClass,
    'subjects': subjects,
  };

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) => AppUser(
    uid: uid,
    fullName: data['fullName'] as String? ?? '',
    email: data['email'] as String? ?? '',
    studentClass: data['class'] as String?,
    subjects: List<String>.from(data['subjects'] as List? ?? const []),
  );
}
