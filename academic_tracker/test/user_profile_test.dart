import 'package:academic_tracker/models/app_user.dart';
import 'package:academic_tracker/planner_repository.dart';
import 'package:academic_tracker/user_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository users;
  const riya = AppUser(
    uid: 'uid-1',
    fullName: 'Riya Sharma',
    email: 'riya@example.com',
    studentClass: 'Class 10',
    subjects: ['Physics'],
  );

  Future<Map<String, dynamic>?> stored(String uid) async =>
      (await profileDoc(firestore, uid).get()).data();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    firestore = FakeFirebaseFirestore();
    users = UserRepository(firestore: firestore);
  });

  test('AppUser round-trips, storing exactly the four fields', () {
    final map = riya.toMap();
    expect(
      map.keys,
      unorderedEquals(['fullName', 'email', 'class', 'subjects']),
    );
    final restored = AppUser.fromMap('uid-1', map);
    expect(restored.uid, 'uid-1');
    expect(restored.fullName, 'Riya Sharma');
    expect(restored.email, 'riya@example.com');
    expect(restored.studentClass, 'Class 10');
    expect(restored.subjects, ['Physics']);
  });

  test('AppUser tolerates a document with missing fields', () {
    final user = AppUser.fromMap('uid-1', {'email': 'riya@example.com'});
    expect(user.fullName, '');
    expect(user.studentClass, isNull);
    expect(user.subjects, isEmpty);
  });

  test('saveProfile uses the UID as the document ID', () async {
    await users.saveProfile(riya);
    expect(await stored('uid-1'), {
      'fullName': 'Riya Sharma',
      'email': 'riya@example.com',
      'class': 'Class 10',
      'subjects': ['Physics'],
    });
  });

  test('saveProfile keeps subjects added before sign-up finished', () async {
    await FirestorePlanner(
      'uid-1',
      firestore: firestore,
    ).addSubjects(['Physics']);
    await users.saveProfile(
      const AppUser(
        uid: 'uid-1',
        fullName: 'Riya S',
        email: 'riya@example.com',
        studentClass: 'Class 11',
      ),
    );
    final data = await stored('uid-1');
    expect(data!['fullName'], 'Riya S');
    expect(data['class'], 'Class 11');
    expect(data['subjects'], ['Physics']);
  });

  test('ensureProfile fills only the fields that are missing', () async {
    await FirestorePlanner(
      'uid-1',
      firestore: firestore,
    ).addSubjects(['Physics']);
    await users.ensureProfile(
      const AppUser(uid: 'uid-1', fullName: 'Riya', email: 'riya@example.com'),
    );
    expect(await stored('uid-1'), {
      'fullName': 'Riya',
      'email': 'riya@example.com',
      'class': null,
      'subjects': ['Physics'],
    });
    await users.ensureProfile(
      const AppUser(uid: 'uid-1', fullName: 'Changed', email: 'x@example.com'),
    );
    expect((await stored('uid-1'))!['fullName'], 'Riya');
  });

  test('Profile fields on users/{uid} move into profile/info', () async {
    final root = firestore.collection('users').doc('uid-1');
    await root.set({
      'fullName': 'Old name',
      'email': 'riya@example.com',
      'class': null,
      'subjects': ['Physics'],
    });
    await root.collection('items').doc('a').set({'title': 'kept'});
    await FirestorePlanner(
      'uid-1',
      firestore: firestore,
    ).addSubjects(['Maths']);
    await users.ensureProfile(
      const AppUser(uid: 'uid-1', fullName: 'Ignored', email: 'x@example.com'),
    );
    final profile = await stored('uid-1');
    expect(profile!['fullName'], 'Old name');
    expect(profile['email'], 'riya@example.com');
    expect(profile.containsKey('class'), isTrue);
    expect(profile['subjects'], unorderedEquals(['Physics', 'Maths']));
    expect((await root.get()).data(), isEmpty);
    expect((await root.collection('items').doc('a').get()).exists, isTrue);
  });

  test('The planner reads subjects that were left on users/{uid}', () async {
    await firestore.collection('users').doc('uid-1').set({
      'subjects': ['History'],
    });
    final data = await FirestorePlanner('uid-1', firestore: firestore).load();
    expect(data.subjects, ['History']);
  });
}
