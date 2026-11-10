import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'study_store.dart';
import 'user_repository.dart';

/// Stores a user's planner in their account:
///
/// * `users/{uid}/items/{itemId}` holds one task or event per document.
/// * `users/{uid}/profile/info` holds their subjects, with their profile.
/// * `users/{uid}/progress/{yyyy-MM}` counts tasks completed that month.
class FirestorePlanner implements PlannerBackend {
  FirestorePlanner(this.uid, {this._firestore});

  final String uid;
  final FirebaseFirestore? _firestore;

  // Resolved on use, so constructing a planner in tests never needs Firebase.
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get _profile => profileDoc(_db, uid);
  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('users').doc(uid).collection('items');
  CollectionReference<Map<String, dynamic>> get _progress =>
      _db.collection('users').doc(uid).collection('progress');

  Map<String, dynamic> _countChange(String month, int by) => {
    'month': month,
    'completed': FieldValue.increment(by),
  };

  /// Where older versions of the app kept this user's planner on the device.
  String get _legacyKey => 'study-flow-planner-v1-$uid';

  @override
  Future<PlannerSnapshot> load() async {
    await _uploadLegacyData();
    try {
      // Subjects may still be on users/{uid} from an earlier version.
      await moveLegacyProfile(_db, uid);
    } catch (e) {
      debugPrint('Could not move the old profile fields: $e');
    }
    final itemDocs = await _items.get();
    final profile = await _profile.get();
    final items = <StudyItem>[];
    final finished = <StudyItem>[];
    for (final doc in itemDocs.docs) {
      try {
        final item = itemFromMap(doc.id, doc.data());
        (item.completed && !item.isEvent ? finished : items).add(item);
      } catch (e) {
        debugPrint('Skipping unreadable planner item ${doc.id}: $e');
      }
    }
    final progressDocs = await _progress.get();
    final progress = {
      for (final doc in progressDocs.docs)
        doc.id: (doc.data()['completed'] as num? ?? 0).toInt(),
    };
    // Counted after reading, so the result is right whether or not the write
    // below has reached the cache yet.
    if (finished.isNotEmpty) {
      _countOldCompletedTasks(finished).forEach((month, added) {
        progress[month] = (progress[month] ?? 0) + added;
      });
    }
    final subjects = List<String>.from(
      profile.data()?['subjects'] as List? ?? const [],
    );
    return PlannerSnapshot(
      items: items,
      subjects: subjects,
      progress: progress,
    );
  }

  @override
  Future<void> saveItem(StudyItem item) =>
      _items.doc(item.id).set(itemToMap(item));

  @override
  Future<void> deleteItem(String id) => _items.doc(id).delete();

  @override
  Future<void> completeTask(StudyItem task, String month) {
    final batch = _db.batch()
      ..delete(_items.doc(task.id))
      ..set(
        _progress.doc(month),
        _countChange(month, 1),
        SetOptions(merge: true),
      );
    return batch.commit();
  }

  @override
  Future<void> restoreTask(StudyItem task, String month) {
    final batch = _db.batch()
      ..set(_items.doc(task.id), itemToMap(task))
      ..set(
        _progress.doc(month),
        _countChange(month, -1),
        SetOptions(merge: true),
      );
    return batch.commit();
  }

  /// Older versions kept completed tasks. Count each one towards the month it
  /// was due (the closest record of when it was done) and delete it. Returns
  /// the counts added. The write is not awaited, so loading never waits on
  /// the network; offline it is sent later.
  Map<String, int> _countOldCompletedTasks(List<StudyItem> tasks) {
    final perMonth = <String, int>{};
    final batch = _db.batch();
    for (final task in tasks) {
      final month = StudyStore.monthKey(task.date);
      perMonth[month] = (perMonth[month] ?? 0) + 1;
      batch.delete(_items.doc(task.id));
    }
    for (final entry in perMonth.entries) {
      batch.set(
        _progress.doc(entry.key),
        _countChange(entry.key, entry.value),
        SetOptions(merge: true),
      );
    }
    unawaited(
      batch.commit().catchError(
        (Object e) => debugPrint('Could not count old completed tasks: $e'),
      ),
    );
    return perMonth;
  }

  @override
  Future<void> addSubjects(List<String> names) => _profile.set({
    'subjects': FieldValue.arrayUnion(names),
  }, SetOptions(merge: true));

  @override
  Future<void> saveAll(List<StudyItem> items, List<String> subjects) async {
    // A batch holds at most 500 writes.
    for (var start = 0; start < items.length; start += 450) {
      final batch = _db.batch();
      for (final item in items.skip(start).take(450)) {
        batch.set(_items.doc(item.id), itemToMap(item));
      }
      await batch.commit();
    }
    if (subjects.isNotEmpty) await addSubjects(subjects);
  }

  /// Moves anything an older version saved on the device into the account,
  /// then deletes the device copy. Never blocks loading: if it fails or the
  /// device is offline, the device copy stays and is retried next launch.
  /// Re-uploading is harmless because items are written by their own ID.
  Future<void> _uploadLegacyData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final items = (data['items'] as List? ?? const [])
          .map((i) => StudyItem.fromJson(Map<String, dynamic>.from(i as Map)))
          .toList();
      final subjects = List<String>.from(data['subjects'] as List? ?? const []);
      await saveAll(items, subjects).timeout(const Duration(seconds: 15));
      await prefs.remove(_legacyKey);
    } catch (e) {
      debugPrint('Could not move on-device planner data to the account: $e');
    }
  }
}

/// Firestore form of a [StudyItem]. Dates are stored as timestamps so they can
/// be sorted and queried on the server.
Map<String, dynamic> itemToMap(StudyItem item) => {
  'title': item.title,
  'date': Timestamp.fromDate(item.date),
  'endTime': item.endTime == null ? null : Timestamp.fromDate(item.endTime!),
  'isEvent': item.isEvent,
  'hasTime': item.hasTime,
  'completed': item.completed,
  'subject': item.subject,
  'priority': item.priority,
  'type': item.type,
  'description': item.description,
  'updatedAt': FieldValue.serverTimestamp(),
};

StudyItem itemFromMap(String id, Map<String, dynamic> data) => StudyItem(
  id: id,
  title: data['title'] as String,
  date: (data['date'] as Timestamp).toDate(),
  endTime: (data['endTime'] as Timestamp?)?.toDate(),
  isEvent: data['isEvent'] == true,
  hasTime: data['hasTime'] == true,
  completed: data['completed'] == true,
  subject: data['subject'] as String? ?? '',
  priority: data['priority'] as String? ?? 'Medium',
  type: data['type'] as String? ?? 'Task',
  description: data['description'] as String? ?? '',
);
