import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/app_user.dart';

/// Layout of a user's data, keyed by Firebase Auth UID:
///
/// ```
/// users/{uid}/profile/info    fullName, email, class, subjects
/// users/{uid}/items/{itemId}  one task or event each
/// ```
///
/// A Firestore collection can only hold documents, so `profile` holds a single
/// document, `info`, which carries the fields.
DocumentReference<Map<String, dynamic>> profileDoc(
  FirebaseFirestore db,
  String uid,
) => db.collection('users').doc(uid).collection('profile').doc('info');

const _profileFields = ['fullName', 'email', 'class', 'subjects'];

/// Earlier versions stored the profile fields directly on `users/{uid}`. This
/// moves any it finds into `profile/info`, keeping values already there and
/// combining subjects, then removes them from `users/{uid}`. Running it again
/// once they have moved does nothing.
Future<void> moveLegacyProfile(FirebaseFirestore db, String uid) {
  final root = db.collection('users').doc(uid);
  final profile = profileDoc(db, uid);
  return db.runTransaction<void>((transaction) async {
    final legacy = (await transaction.get(root)).data() ?? const {};
    final current = (await transaction.get(profile)).data();
    final moving = {
      for (final key in _profileFields)
        if (legacy.containsKey(key)) key: legacy[key],
    };
    if (moving.isEmpty) return;

    final updates = <String, dynamic>{
      for (final entry in moving.entries)
        if (entry.key != 'subjects' &&
            (current == null || !current.containsKey(entry.key)))
          entry.key: entry.value,
    };
    final oldSubjects = List<String>.from(moving['subjects'] as List? ?? []);
    final subjects = {
      ...List<String>.from(current?['subjects'] as List? ?? []),
      ...oldSubjects,
    }.toList();
    if (current == null || oldSubjects.isNotEmpty) {
      updates['subjects'] = subjects;
    }

    if (current == null) {
      transaction.set(profile, updates);
    } else if (updates.isNotEmpty) {
      transaction.update(profile, updates);
    }
    transaction.update(root, {
      for (final key in moving.keys) key: FieldValue.delete(),
    });
  });
}

/// Reads and writes each user's `profile/info` document.
class UserRepository {
  UserRepository({this._firestore});

  final FirebaseFirestore? _firestore;

  // Resolved on use, so building a Home in tests never needs Firebase.
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Writes the details collected at sign-up. A merge, because Home may have
  /// already created this document: the auth state changes as soon as the
  /// account exists, before the sign-up form has finished.
  Future<void> saveProfile(AppUser user) => profileDoc(_db, user.uid).set({
    ...user.toMap(),
    'subjects': FieldValue.arrayUnion(user.subjects),
  }, SetOptions(merge: true));

  /// Live profile. Includes cache-only updates, so the caller can tell a
  /// "not on this device yet" result from a confirmed empty profile.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchProfile(String uid) =>
      profileDoc(_db, uid).snapshots(includeMetadataChanges: true);

  /// Writes the given fields, leaving the others as they are.
  Future<void> updateProfile(String uid, Map<String, dynamic> fields) =>
      profileDoc(_db, uid).set(fields, SetOptions(merge: true));

  /// Fills in whichever of the four profile fields the document is missing,
  /// creating it if needed, and never overwrites a field that already exists.
  /// This covers Google sign-in, accounts created before profiles existed,
  /// and a document that a subject write created first.
  Future<void> ensureProfile(AppUser user) async {
    await moveLegacyProfile(_db, user.uid);
    final doc = profileDoc(_db, user.uid);
    await _db.runTransaction<void>((transaction) async {
      final data = (await transaction.get(doc)).data();
      final missing = {
        for (final entry in user.toMap().entries)
          if (data == null || !data.containsKey(entry.key))
            entry.key: entry.value,
      };
      if (data == null) {
        transaction.set(doc, missing);
      } else if (missing.isNotEmpty) {
        transaction.update(doc, missing);
      }
    });
  }
}
