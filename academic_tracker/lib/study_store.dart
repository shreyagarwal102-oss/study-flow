import 'package:flutter/material.dart';

DateTime dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);
const months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
String dateLabel(DateTime date, {bool full = false, DateTime? today}) {
  if (full) {
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }
  final reference = today ?? dayOnly(DateTime.now());
  if (dayOnly(date) == reference) return 'Today';
  if (dayOnly(date) == reference.add(const Duration(days: 1))) {
    return 'Tomorrow';
  }
  return '${date.day} ${months[date.month - 1].substring(0, 3)} ${date.year}';
}

String timeLabel(BuildContext context, DateTime date) =>
    TimeOfDay.fromDateTime(date).format(context);

class StudyItem {
  const StudyItem({
    required this.id,
    required this.title,
    required this.date,
    this.isEvent = false,
    this.hasTime = false,
    this.completed = false,
    this.subject = '',
    this.priority = 'Medium',
    this.type = 'Task',
    this.description = '',
    this.endTime,
  });
  final String id, title, subject, priority, type, description;
  final DateTime date;
  final DateTime? endTime;
  final bool isEvent, hasTime, completed;

  // Keep historical records, but hide completed tasks dated before today.
  // Callers filtering a whole list pass `today` once instead of paying a
  // DateTime.now() per item.
  bool isVisibleOn(DateTime today) =>
      isEvent || !completed || !dayOnly(date).isBefore(today);
  bool get isVisible => isVisibleOn(dayOnly(DateTime.now()));

  StudyItem copy({bool? completed}) => StudyItem(
    id: id,
    title: title,
    date: date,
    isEvent: isEvent,
    hasTime: hasTime,
    completed: completed ?? this.completed,
    subject: subject,
    priority: priority,
    type: type,
    description: description,
    endTime: endTime,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date.toIso8601String(),
    'isEvent': isEvent,
    'hasTime': hasTime,
    'completed': completed,
    'subject': subject,
    'priority': priority,
    'type': type,
    'description': description,
    'endTime': endTime?.toIso8601String(),
  };
  factory StudyItem.fromJson(Map<String, dynamic> json) => StudyItem(
    id: json['id'] as String,
    title: json['title'] as String,
    date: DateTime.parse(json['date'] as String),
    isEvent: json['isEvent'] == true,
    hasTime: json['hasTime'] == true,
    completed: json['completed'] == true,
    subject: json['subject'] as String? ?? '',
    priority: json['priority'] as String? ?? 'Medium',
    type: json['type'] as String? ?? 'Task',
    description: json['description'] as String? ?? '',
    endTime: json['endTime'] == null
        ? null
        : DateTime.parse(json['endTime'] as String),
  );
}

/// Everything a user has in their planner, as loaded from their account.
class PlannerSnapshot {
  const PlannerSnapshot({
    required this.items,
    required this.subjects,
    this.progress = const {},
  });
  final List<StudyItem> items;
  final List<String> subjects;

  /// Tasks completed per month, keyed by [StudyStore.monthKey].
  final Map<String, int> progress;
}

/// Where a planner is stored. The app uses the Firestore implementation;
/// tests can substitute their own.
abstract class PlannerBackend {
  Future<PlannerSnapshot> load();
  Future<void> saveItem(StudyItem item);
  Future<void> deleteItem(String id);
  Future<void> addSubjects(List<String> names);

  /// Deletes the task and adds one to [month]'s completed count, together.
  Future<void> completeTask(StudyItem task, String month);

  /// Reverses [completeTask]: puts the task back and takes one off [month].
  Future<void> restoreTask(StudyItem task, String month);

  /// Rewrites everything, used to recover after a failed save.
  Future<void> saveAll(List<StudyItem> items, List<String> subjects);
}

class StudyStore extends ChangeNotifier {
  /// With no [backend], the planner lives only in memory (used by tests and by
  /// a signed-out Home).
  StudyStore({this.backend, List<StudyItem>? initialItems})
    : items = [...?initialItems];
  final PlannerBackend? backend;
  final List<StudyItem> items;
  final List<String> subjects = [];

  /// Tasks completed per month, keyed by [monthKey]. Completed tasks are
  /// deleted, so this count is all that remains of them.
  final Map<String, int> monthlyProgress = {};
  bool loading = false;
  bool _disposed = false;
  bool _loadFailed = false;
  String? error;
  Future<void>? _loadFuture;

  // Sorted visible items, rebuilt only when the data or the calendar day
  // changes. Widgets can read this per cell without re-sorting the list.
  List<StudyItem>? _visibleCache;
  DateTime? _visibleCacheDay;

  static const _loadError =
      'Could not load your planner. Check your connection and retry.';
  static const _saveError =
      'A change could not be saved to your account. Check your connection and retry.';

  /// "2026-11" for November 2026: sorts by date and names a progress document.
  static String monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  void _notify() {
    _visibleCache = null;
    if (!_disposed) notifyListeners();
  }

  /// Visible items ordered by date. Memoised, so the calendar grid and the
  /// subject list can call it per cell without recomputing a sort each time.
  List<StudyItem> visibleItems() {
    final today = dayOnly(DateTime.now());
    final cached = _visibleCache;
    if (cached != null && _visibleCacheDay == today) return cached;
    final computed = items.where((i) => i.isVisibleOn(today)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    _visibleCacheDay = today;
    return _visibleCache = computed;
  }

  Future<void> load() {
    if (backend == null) return Future.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    loading = true;
    try {
      final data = await backend!.load();
      items.addAll(data.items);
      subjects.addAll(data.subjects.where((s) => !subjects.contains(s)));
      monthlyProgress.addAll(data.progress);
      error = null;
      _loadFailed = false;
    } catch (e) {
      debugPrint('Planner load failed: $e');
      _loadFailed = true;
      error = _loadError;
    }
    loading = false;
    _notify();
  }

  /// A mutation that arrives while the first load is still running waits for
  /// it rather than being dropped, so an early tap is not silently lost.
  Future<bool> _ready() async {
    final pending = _loadFuture;
    if (pending != null) await pending;
    if (_loadFailed) {
      error = _loadError;
      _notify();
      return false;
    }
    return true;
  }

  /// The change is already on screen; this only reports whether the account
  /// accepted it. Firestore queues writes made offline and sends them later.
  Future<void> _write(Future<void> Function(PlannerBackend backend) op) async {
    final target = backend;
    if (target == null) return;
    try {
      await op(target);
      if (error == _saveError) {
        error = null;
        _notify();
      }
    } catch (e) {
      debugPrint('Planner save failed: $e');
      error = _saveError;
      _notify();
    }
  }

  Future<void> saveItem(StudyItem item) async {
    if (!await _ready()) return;
    final index = items.indexWhere((i) => i.id == item.id);
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }
    final newSubject =
        item.subject.isNotEmpty && !subjects.contains(item.subject);
    if (newSubject) subjects.add(item.subject);
    _notify();
    await _write(
      (b) => Future.wait([
        b.saveItem(item),
        if (newSubject) b.addSubjects([item.subject]),
      ]),
    );
  }

  /// Completing a task removes it and counts it towards [month], which
  /// defaults to the current month. An event only toggles its completed flag:
  /// events never count towards progress.
  Future<void> completeTask(StudyItem item, {String? month}) async {
    if (item.isEvent) {
      await saveItem(item.copy(completed: !item.completed));
      return;
    }
    if (!await _ready()) return;
    final key = month ?? monthKey(DateTime.now());
    items.removeWhere((i) => i.id == item.id);
    monthlyProgress[key] = (monthlyProgress[key] ?? 0) + 1;
    _notify();
    await _write((b) => b.completeTask(item, key));
  }

  /// Undo for [completeTask].
  Future<void> undoComplete(StudyItem task, String month) async {
    if (!await _ready()) return;
    if (!items.any((i) => i.id == task.id)) items.add(task);
    final count = (monthlyProgress[month] ?? 0) - 1;
    if (count > 0) {
      monthlyProgress[month] = count;
    } else {
      monthlyProgress.remove(month);
    }
    _notify();
    await _write((b) => b.restoreTask(task, month));
  }

  Future<void> deleteItem(String id) async {
    if (!await _ready()) return;
    items.removeWhere((i) => i.id == id);
    _notify();
    await _write((b) => b.deleteItem(id));
  }

  Future<void> addSubject(String name) async {
    if (!await _ready()) return;
    if (subjects.contains(name)) return;
    subjects.add(name);
    _notify();
    await _write((b) => b.addSubjects([name]));
  }

  /// Banner action: re-read after a failed load, otherwise re-send everything.
  Future<void> retrySave() {
    if (_loadFailed) {
      _loadFuture = null;
      return load();
    }
    return _write((b) => b.saveAll(List.of(items), List.of(subjects)));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
