import 'dart:convert';
import 'package:academic_tracker/planner_repository.dart';
import 'package:academic_tracker/screens/home.dart';
import 'package:academic_tracker/study_store.dart';
import 'package:academic_tracker/study_theme.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    firestore = FakeFirebaseFirestore();
  });
  StudyStore account(String uid) =>
      StudyStore(backend: FirestorePlanner(uid, firestore: firestore));
  final today = dayOnly(DateTime.now());
  StudyItem task(
    String id,
    int offset, {
    bool completed = false,
    bool event = false,
  }) => StudyItem(
    id: id,
    title: id,
    date: DateTime(today.year, today.month, today.day + offset),
    completed: completed,
    isEvent: event,
    subject: 'Physics',
  );

  test('Only current and future completed tasks stay visible', () {
    expect(task('old done', -1, completed: true).isVisible, isFalse);
    expect(task('overdue', -1).isVisible, isTrue);
    expect(task('today done', 0, completed: true).isVisible, isTrue);
    expect(task('future done', 1, completed: true).isVisible, isTrue);
    expect(
      task('past event', -1, completed: true, event: true).isVisible,
      isTrue,
    );
  });

  test('Planner saves to the account and isolates users', () async {
    final first = account('one');
    await first.load();
    final timed = StudyItem(
      id: 'Exam',
      title: 'Physics exam',
      date: DateTime(today.year, today.month, today.day, 9, 30),
      endTime: DateTime(today.year, today.month, today.day, 11),
      hasTime: true,
      isEvent: true,
      subject: 'Physics',
      priority: 'High',
      type: 'Exam',
      description: 'Chapters 1-4',
    );
    await first.saveItem(task('Homework', 0));
    await first.saveItem(
      StudyItem(
        id: 'Homework',
        title: 'Homework v2',
        date: task('Homework', 0).date,
        subject: 'Physics',
      ),
    );
    await first.saveItem(timed);
    final restored = account('one');
    await restored.load();
    final homework = restored.items.firstWhere((i) => i.id == 'Homework');
    expect(homework.title, 'Homework v2');
    final exam = restored.items.firstWhere((i) => i.id == 'Exam');
    expect(exam.date, timed.date);
    expect(exam.endTime, timed.endTime);
    expect(
      [exam.title, exam.hasTime, exam.isEvent, exam.priority, exam.type],
      ['Physics exam', true, true, 'High', 'Exam'],
    );
    expect(exam.description, 'Chapters 1-4');
    expect(restored.subjects, ['Physics']);
    final other = account('two');
    await other.load();
    expect(other.items, isEmpty);
    await restored.deleteItem('Homework');
    final deleted = account('one');
    await deleted.load();
    expect(deleted.items.map((i) => i.id), ['Exam']);
  });

  for (final width in [320.0, 393.0]) {
    testWidgets('All five destinations fit $width and calendar changes month', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = StudyStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: studyTheme(),
          home: Home(displayName: 'Riya Sharma', store: store),
        ),
      );
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.text('CONTINUE STUDYING'), findsNothing);
      expect(find.text('Focused today'), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
      for (final label in ['Calendar', 'Events', 'Tasks', 'Profile']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
        if (label == 'Calendar') {
          await tester.tap(find.byTooltip('Next month'));
          await tester.pumpAndSettle();
          final next = DateTime(today.year, today.month + 1);
          expect(
            find.text('${months[next.month - 1]} ${next.year}'),
            findsOneWidget,
          );
          await tester.tap(find.widgetWithText(TextButton, 'Today'));
          await tester.pumpAndSettle();
          expect(
            find.text('${months[today.month - 1]} ${today.year}'),
            findsOneWidget,
          );
        }
      }
      expect(find.text('My Subjects'), findsWidgets);
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      expect(
        find.text('0 tasks completed in ${months[today.month - 1]}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Add task updates calendar and filtered task list; completion removes old tasks',
    (tester) async {
      final store = StudyStore(
        initialItems: [
          task('Old completed homework', -1, completed: true),
          task('Overdue homework', -1),
          task('Today completed homework', 0, completed: true),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: studyTheme(),
          home: Home(store: store),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Calendar'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Add event'), findsOneWidget);
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title *'),
        'Practice optics',
      );
      await tester.tap(find.text('Save task'));
      await tester.pumpAndSettle();
      expect(store.items.any((i) => i.title == 'Practice optics'), isTrue);
      expect(find.text('Practice optics'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Tasks'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old completed homework'), findsNothing);
      expect(find.text('Overdue homework'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Search tasks'),
        'Practice',
      );
      // Search is debounced, so advance past the window before asserting.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Practice optics'), findsOneWidget);
      expect(find.text('Overdue homework'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Search tasks'),
        '',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overdue homework'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark complete'));
      await tester.pumpAndSettle();
      expect(find.text('Overdue homework'), findsNothing);
      expect(store.items.any((i) => i.title == 'Overdue homework'), isFalse);
      expect(store.monthlyProgress[StudyStore.monthKey(DateTime.now())], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Events can be created, filtered, edited and deleted', (
    tester,
  ) async {
    final store = StudyStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: studyTheme(),
        home: Home(store: store),
      ),
    );
    // Events adds events straight from its header +, with no intermediate
    // "event or task?" sheet and no floating Add button.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Events'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.byTooltip('Add event'));
    await tester.pumpAndSettle();
    expect(find.text('Add task'), findsNothing);
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a title.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title *'),
      'Physics test',
    );
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(store.items.single.isEvent, isTrue);
    expect(store.items.single.type, 'Exam');
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Events'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Physics test'), findsOneWidget);
    await tester.tap(find.text('All types'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Class').last);
    await tester.pumpAndSettle();
    expect(find.text('Physics test'), findsNothing);
    await tester.tap(find.text('Class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All types').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Physics test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit / reschedule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title *'),
      'Physics final',
    );
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(store.items.single.title, 'Physics final');
    await tester.tap(find.text('Physics final'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(store.items, isEmpty);
    expect(find.text('Physics final'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('Visible items are memoised until the data changes', () async {
    final store = StudyStore(initialItems: [task('A', 0), task('B', 1)]);
    final first = store.visibleItems();
    expect(store.visibleItems(), same(first), reason: 'repeat read is cached');
    await store.saveItem(task('C', 2));
    expect(store.visibleItems(), isNot(same(first)));
    expect(store.visibleItems().map((i) => i.title), ['A', 'B', 'C']);
  });

  test('A mutation during the first load is queued, not dropped', () async {
    final store = account('queued');
    final loading = store.load();
    final saving = store.saveItem(task('Early tap', 0));
    await Future.wait([loading, saving]);
    expect(store.items.map((i) => i.title), ['Early tap']);
    final restored = account('queued');
    await restored.load();
    expect(restored.items.single.title, 'Early tap');
  });

  test('Planner data left on the device moves to the account once', () async {
    const key = 'study-flow-planner-v1-one';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({
        'items': [task('Old homework', 0).toJson()],
        'subjects': ['Physics', 'Maths'],
      }),
    });
    final store = account('one');
    await store.load();
    expect(store.items.single.title, 'Old homework');
    expect(store.subjects, ['Physics', 'Maths']);
    expect((await SharedPreferences.getInstance()).getString(key), isNull);
    final again = account('one');
    await again.load();
    expect(again.items.length, 1);
  });

  test('Completing a task deletes it and counts it for the month', () async {
    final store = account('one');
    await store.load();
    await store.saveItem(task('Homework', 0));
    await store.saveItem(task('Essay', 1));
    await store.completeTask(store.items.first, month: '2026-11');
    expect(store.items.map((i) => i.title), ['Essay']);
    expect(store.monthlyProgress, {'2026-11': 1});

    final restored = account('one');
    await restored.load();
    expect(restored.items.map((i) => i.title), ['Essay']);
    expect(restored.monthlyProgress, {'2026-11': 1});
    final progressDoc = await firestore
        .collection('users')
        .doc('one')
        .collection('progress')
        .doc('2026-11')
        .get();
    expect(progressDoc.data()!['completed'], 1);
  });

  test('Undo puts the task back and takes it off the count', () async {
    final store = account('one');
    await store.load();
    final homework = task('Homework', 0);
    await store.saveItem(homework);
    await store.completeTask(homework, month: '2026-11');
    await store.undoComplete(homework, '2026-11');
    expect(store.items.single.title, 'Homework');
    expect(store.monthlyProgress, isEmpty);
    final restored = account('one');
    await restored.load();
    expect(restored.items.single.title, 'Homework');
    expect(restored.monthlyProgress['2026-11'] ?? 0, 0);
  });

  test('Events never count towards progress', () async {
    final store = account('one');
    await store.load();
    final exam = task('Exam', 0, event: true);
    await store.saveItem(exam);
    await store.completeTask(exam, month: '2026-11');
    expect(store.items.single.completed, isTrue);
    expect(store.monthlyProgress, isEmpty);
  });

  test('Completed tasks from older versions become counts', () async {
    final items = firestore.collection('users').doc('one').collection('items');
    await items
        .doc('old')
        .set(
          itemToMap(
            StudyItem(
              id: 'old',
              title: 'Old',
              date: DateTime(2026, 10, 3),
              completed: true,
            ),
          ),
        );
    await items
        .doc('open')
        .set(
          itemToMap(
            StudyItem(id: 'open', title: 'Open', date: DateTime(2026, 11, 3)),
          ),
        );
    final store = account('one');
    await store.load();
    expect(store.items.map((i) => i.id), ['open']);
    expect(store.monthlyProgress, {'2026-10': 1});
    expect((await items.doc('old').get()).exists, isFalse);
  });

  test('A failed save keeps the change and Retry re-sends it', () async {
    final backend = _FlakyBackend();
    final store = StudyStore(backend: backend);
    await store.load();
    backend.failing = true;
    await store.saveItem(task('Homework', 0));
    expect(store.items.single.title, 'Homework');
    expect(store.error, isNotNull);
    backend.failing = false;
    await store.retrySave();
    expect(store.error, isNull);
    expect(backend.saved.single.title, 'Homework');
  });

  testWidgets('Search is debounced and applies only the final query', (
    tester,
  ) async {
    final store = StudyStore(
      initialItems: [task('Optics revision', 0), task('Algebra revision', 0)],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: studyTheme(),
        home: Home(store: store),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Tasks'),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, 'Search tasks');
    await tester.enterText(field, 'Opt');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(field, 'Algebra');
    await tester.pump(const Duration(milliseconds: 100));
    // Inside the debounce window nothing has been re-filtered yet.
    expect(find.text('Optics revision'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Algebra revision'), findsOneWidget);
    expect(find.text('Optics revision'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Only the calendar has a floating Add; listings add their own kind',
    (tester) async {
      final store = StudyStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: studyTheme(),
          home: Home(store: store),
        ),
      );
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'Home has no floating Add',
      );
      for (final entry in {
        'Calendar': true,
        'Events': false,
        'Tasks': false,
        'Profile': false,
      }.entries) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(entry.key),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(FloatingActionButton),
          entry.value ? findsOneWidget : findsNothing,
          reason: entry.key,
        );
      }
      // Each listing page offers exactly one kind, not a chooser.
      for (final entry in {'Tasks': 'task', 'Events': 'event'}.entries) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(entry.key),
          ),
        );
        await tester.pumpAndSettle();
        final other = entry.value == 'task' ? 'event' : 'task';
        expect(find.byTooltip('Add ${entry.value}'), findsOneWidget);
        expect(find.byTooltip('Add $other'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Empty state cards span the full content width', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = StudyStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: studyTheme(),
        home: Home(store: store),
      ),
    );
    // The ListView pads 20 on each side; a card must use everything left.
    final expected = tester.getSize(find.byType(ListView)).width - 40;
    for (final entry in {
      'Home': 'Nothing due today',
      'Calendar': 'A little room in your day',
      'Tasks': 'No tasks here',
      'Events': 'No events here',
      'Profile': 'No subjects added yet',
    }.entries) {
      if (entry.key != 'Home') {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(entry.key),
          ),
        );
        await tester.pumpAndSettle();
      }
      final card = find
          .ancestor(
            of: find.text(entry.value),
            matching: find.byType(StudyCard),
          )
          .first;
      expect(
        tester.getSize(card).width,
        expected,
        reason: '${entry.key} empty card should fill the width',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Switching tabs resets the scroll offset', (tester) async {
    final store = StudyStore(
      initialItems: [for (var i = 0; i < 40; i++) task('Task number $i', i)],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: studyTheme(),
        home: Home(store: store),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Tasks'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrolled = tester.widget<ListView>(find.byType(ListView));
    expect(scrolled.controller!.offset, greaterThan(0));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
    );
    await tester.pumpAndSettle();
    expect(scrolled.controller!.offset, 0);
    expect(tester.takeException(), isNull);
  });
}

class _FlakyBackend implements PlannerBackend {
  bool failing = false;
  List<StudyItem> saved = [];
  Future<void> _check() async {
    if (failing) throw StateError('offline');
  }

  @override
  Future<PlannerSnapshot> load() async =>
      const PlannerSnapshot(items: [], subjects: []);
  @override
  Future<void> saveItem(StudyItem item) => _check();
  @override
  Future<void> deleteItem(String id) => _check();
  @override
  Future<void> addSubjects(List<String> names) => _check();
  @override
  Future<void> completeTask(StudyItem task, String month) => _check();
  @override
  Future<void> restoreTask(StudyItem task, String month) => _check();
  @override
  Future<void> saveAll(List<StudyItem> items, List<String> subjects) async {
    await _check();
    saved = items;
  }
}
