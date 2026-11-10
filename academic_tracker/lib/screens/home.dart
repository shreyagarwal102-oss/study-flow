import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../planner_repository.dart';
import '../study_theme.dart';
import '../study_store.dart';
import 'item_editor.dart';

class Home extends StatefulWidget {
  const Home({
    super.key,
    this.displayName,
    this.userId,
    this.store,
    this.searchDebounce = const Duration(milliseconds: 250),
  });
  final String? displayName;
  final String? userId;
  final StudyStore? store;

  /// Typing re-filters the whole list, so keystrokes are coalesced.
  final Duration searchDebounce;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  late final StudyStore store;
  int tab = 0;
  DateTime selectedDay = dayOnly(DateTime.now());
  late DateTime month = DateTime(selectedDay.year, selectedDay.month);
  String taskStatus = 'All', eventStatus = 'All', subject = 'All subjects';
  String dateFilter = 'Any date', priority = 'Any priority', search = '';
  String eventType = 'All types';
  DateTime? customDate;
  bool showProgress = false;

  // One clock reading per build, shared by every widget in the tree. Previously
  // each list row and each calendar cell called DateTime.now() itself.
  DateTime _now = DateTime.now();
  DateTime _today = dayOnly(DateTime.now());

  // Owned by the state so switching tabs can reset the scroll offset without a
  // ValueKey teardown, and can clear the query the filters are reset to.
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchField = TextEditingController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = widget.userId;
    store =
        widget.store ??
        StudyStore(backend: uid == null ? null : FirestorePlanner(uid));
    store.addListener(_refresh);
    store.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchTimer?.cancel();
    _searchField.dispose();
    _scroll.dispose();
    store.removeListener(_refresh);
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  List<StudyItem> get visible => store.visibleItems();

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    if (value == search) return;
    _searchTimer = Timer(widget.searchDebounce, () {
      if (mounted) setState(() => search = value);
    });
  }

  void _navigate(int value) {
    _searchTimer?.cancel();
    _searchField.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      tab = value;
      subject = 'All subjects';
      dateFilter = 'Any date';
      priority = 'Any priority';
      eventType = 'All types';
      search = '';
      customDate = null;
    });
  }

  Future<void> _edit({StudyItem? item, bool isEvent = false}) async {
    final result = await Navigator.of(context).push<StudyItem>(
      MaterialPageRoute(
        builder: (_) => ItemEditor(
          item: item,
          isEvent: item?.isEvent ?? isEvent,
          date: tab == 1 ? selectedDay : dayOnly(DateTime.now()),
          subjects: store.subjects,
        ),
      ),
    );
    if (result != null && mounted) await store.saveItem(result);
  }

  Future<void> _add() async {
    final event = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add to your planner',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.event_outlined, color: studyBlue),
                title: const Text('Add event'),
                subtitle: const Text(
                  'An exam, class, meeting or personal event',
                ),
                onTap: () => Navigator.pop(context, true),
              ),
              ListTile(
                leading: const Icon(Icons.check_box_outlined, color: studyBlue),
                title: const Text('Add task'),
                subtitle: const Text('Something you need to get done'),
                onTap: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (event != null && mounted) await _edit(isEvent: event);
  }

  Widget _heading(String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: studyMuted,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
  // The parent Columns use CrossAxisAlignment.start, which passes loose width
  // constraints, and nothing inside this card forces a width of its own the way
  // a ListTile or a LinearProgressIndicator does. Without this the card would
  // shrink to the width of its longest line.
  Widget _empty(String title, String detail) => SizedBox(
    width: double.infinity,
    child: StudyCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            const Icon(
              Icons.event_available_outlined,
              color: studyBlue,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: studyMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _item(StudyItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: StudyCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        leading: item.isEvent
            ? const Icon(Icons.event_outlined, color: studyBlue)
            : Checkbox(value: false, onChanged: (_) => _complete(item)),
        title: Text(
          item.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            decoration: item.completed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            [
              dateLabel(item.date, today: _today),
              if (item.hasTime) timeLabel(context, item.date),
              if (item.subject.isNotEmpty) item.subject,
              item.isEvent ? item.type : item.priority,
            ].join(' · '),
            style: TextStyle(
              fontSize: 11,
              color: !item.completed && dayOnly(item.date).isBefore(_today)
                  ? Colors.red.shade700
                  : studyMuted,
            ),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 18, color: studyMuted),
        onTap: () => _details(item),
      ),
    ),
  );

  /// A completed task is deleted and counted towards this month, with Undo to
  /// put it back. An event only toggles its completed flag and never counts.
  void _complete(StudyItem item) {
    if (item.isEvent) {
      store.completeTask(item);
      return;
    }
    final now = DateTime.now();
    final month = StudyStore.monthKey(now);
    store.completeTask(item, month: month);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '"${item.title}" done, added to ${months[now.month - 1]}',
          ),
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.undoComplete(item, month),
          ),
        ),
      );
  }

  Future<void> _details(StudyItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.isEvent ? 'Event' : 'Task',
                style: const TextStyle(color: studyMuted),
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${dateLabel(item.date)}${item.hasTime ? ' · ${timeLabel(context, item.date)}' : ''}',
              ),
              if (item.endTime != null)
                Text('Ends ${timeLabel(context, item.endTime!)}'),
              const SizedBox(height: 8),
              Text('${item.type} · ${item.priority} priority'),
              if (item.subject.isNotEmpty) Text('Subject: ${item.subject}'),
              if (item.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(item.description),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'complete'),
                child: Text(
                  item.isEvent && item.completed
                      ? 'Mark incomplete'
                      : 'Mark complete',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 'edit'),
                      child: const Text('Edit / reschedule'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => Navigator.pop(context, 'delete'),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'complete') {
      _complete(item);
      return;
    }
    if (action == 'edit') {
      await _edit(item: item);
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete “${item.title}”?'),
          content: const Text('This will also remove it from the calendar.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) await store.deleteItem(item.id);
    }
  }

  Widget _upNext(bool event) {
    // Lazy where + firstOrNull stops at the first match instead of
    // materialising the whole matching list to read one element.
    final next = visible
        .where(
          (i) =>
              i.isEvent == event &&
              !i.completed &&
              (i.hasTime
                  ? !i.date.isBefore(_now)
                  : !dayOnly(i.date).isBefore(_today)),
        )
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: next == null
            ? () => _navigate(event ? 2 : 3)
            : () => _details(next),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: event ? const Color(0xFFE9F2FC) : studyInk,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event ? 'UPCOMING EVENT' : 'UP NEXT · TASK',
                      style: TextStyle(
                        fontSize: 10,
                        color: event ? studyMuted : const Color(0xFFBCC9DA),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      next?.title ??
                          (event ? 'No upcoming events' : 'No upcoming tasks'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: event ? studyInk : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      next == null
                          ? 'Add one to plan your day.'
                          : '${dateLabel(next.date, today: _today)}${next.hasTime ? ' · ${timeLabel(context, next.date)}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: event ? studyMuted : const Color(0xFFBCC9DA),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                event ? Icons.event_outlined : Icons.check_box_outlined,
                color: event ? studyBlue : Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _home() {
    final today = _today;
    final todayItems = visible.where((i) => dayOnly(i.date) == today).toList();
    final tasks = todayItems.where((i) => !i.isEvent).toList();
    final due = todayItems.where((i) => !i.completed).toList();
    final name = widget.displayName?.trim();
    final firstName = name == null || name.isEmpty
        ? 'student'
        : name.split(' ').first;
    final hour = _now.hour;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dateLabel(today, full: true),
          style: const TextStyle(color: studyMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          '${hour < 12
              ? 'Good morning'
              : hour < 17
              ? 'Good afternoon'
              : 'Good evening'}, $firstName',
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 22),
        _upNext(false),
        _upNext(true),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metric in [
                ('Tasks today', '${tasks.length}', 3),
                (
                  'Events today',
                  '${todayItems.where((i) => i.isEvent).length}',
                  2,
                ),
                ('Due today', '${due.length}', 1),
              ])
                SizedBox(
                  width: (constraints.maxWidth - 16) / 3,
                  child: InkWell(
                    onTap: () {
                      _navigate(metric.$3);
                      setState(() {
                        dateFilter = 'Today';
                        if (metric.$3 == 1) {
                          selectedDay = today;
                          month = DateTime(today.year, today.month);
                        }
                      });
                    },
                    child: StudyCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.$1,
                            style: const TextStyle(
                              fontSize: 11,
                              color: studyMuted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            metric.$2,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _heading(
          'DUE TODAY',
          action: TextButton(
            onPressed: () {
              _navigate(1);
              setState(() {
                selectedDay = today;
                month = DateTime(today.year, today.month);
              });
            },
            child: const Text('View day'),
          ),
        ),
        if (due.isEmpty)
          _empty(
            'Nothing due today',
            'Your tasks and events for today will appear here.',
          )
        else
          ...due.map(_item),
      ],
    );
  }

  Widget _calendar() {
    final first = DateTime(month.year, month.month);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1;
    final cells = ((count + offset) / 7).ceil() * 7;
    final items = visible.where((i) => dayOnly(i.date) == selectedDay).toList();
    // Bucket once per build. The grid's itemBuilder used to re-scan every item
    // for each of the ~30 day cells it draws.
    final dayBuckets = <DateTime, List<StudyItem>>{};
    for (final item in visible) {
      (dayBuckets[dayOnly(item.date)] ??= <StudyItem>[]).add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Calendar',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                selectedDay = dayOnly(DateTime.now());
                month = DateTime(selectedDay.year, selectedDay.month);
              }),
              child: const Text('Today'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        StudyCard(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${months[month.month - 1]} ${month.year}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: studyMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cells,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: 48,
                ),
                itemBuilder: (context, index) {
                  final number = index - offset + 1;
                  if (number < 1 || number > count) {
                    return const SizedBox.shrink();
                  }
                  final date = DateTime(month.year, month.month, number);
                  final selected = date == selectedDay, today = date == _today;
                  final dayItems = dayBuckets[date] ?? const <StudyItem>[];
                  return Semantics(
                    label: dateLabel(date, full: true),
                    selected: selected,
                    child: InkWell(
                      key: ValueKey('day-${date.toIso8601String()}'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => setState(() => selectedDay = date),
                      child: Column(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? studyBlue : Colors.transparent,
                              shape: BoxShape.circle,
                              border: today && !selected
                                  ? Border.all(color: studyBlue)
                                  : null,
                            ),
                            child: Text(
                              '$number',
                              style: TextStyle(
                                color: selected ? Colors.white : studyInk,
                                fontWeight: selected || today
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final event in [false, true])
                                if (dayItems.any((i) => i.isEvent == event))
                                  Container(
                                    width: 4,
                                    height: 4,
                                    margin: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: event
                                          ? const Color(0xFF8B65D9)
                                          : studyBlue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '● Tasks',
                    style: TextStyle(fontSize: 11, color: studyBlue),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    '● Events',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8B65D9)),
                  ),
                ],
              ),
            ],
          ),
        ),
        _heading(
          dateLabel(selectedDay, full: true),
          action: Text(
            '${items.length} items',
            style: const TextStyle(color: studyMuted, fontSize: 12),
          ),
        ),
        if (items.isEmpty)
          _empty(
            'A little room in your day',
            'Tap Add to plan a task or event for this date.',
          )
        else
          ...items.map(_item),
      ],
    );
  }

  Widget _filter(
    String value,
    List<String> options,
    ValueChanged<String> changed,
  ) => SizedBox(
    width: 150,
    child: DropdownButton<String>(
      value: value,
      isExpanded: true,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: studyInk),
      items: options
          .map(
            (s) => DropdownMenuItem(
              value: s,
              child: Text(s, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) changed(v);
      },
    ),
  );
  Widget _listing(bool event) {
    final status = event ? eventStatus : taskStatus;
    final today = _today;
    final lowerSearch = search.toLowerCase();
    final items = visible.where((i) {
      if (i.isEvent != event) return false;
      final day = dayOnly(i.date);
      if (status == 'Completed' && !i.completed) return false;
      if (status == 'Today' && day != today) return false;
      if (status == 'Upcoming' && (!day.isAfter(today) || i.completed)) {
        return false;
      }
      if (status == 'Overdue' && (!day.isBefore(today) || i.completed)) {
        return false;
      }
      if (subject != 'All subjects' && i.subject != subject) return false;
      if (priority != 'Any priority' && i.priority != priority) return false;
      if (event && eventType != 'All types' && i.type != eventType) {
        return false;
      }
      if (dateFilter == 'Today' && day != today) return false;
      if (dateFilter == 'Next 7 days' &&
          (day.isBefore(today) ||
              !day.isBefore(today.add(const Duration(days: 7))))) {
        return false;
      }
      if (dateFilter == 'Choose date' &&
          customDate != null &&
          day != customDate) {
        return false;
      }
      return i.title.toLowerCase().contains(lowerSearch);
    }).toList();
    final subjects = <String>{
      ...store.subjects,
      ...store.items.map((i) => i.subject).where((s) => s.isNotEmpty),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                event ? 'Events' : 'Tasks',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            // Goes straight to the editor for this page's own kind, so there
            // is no type to pick the way the calendar's Add button asks.
            IconButton.filled(
              onPressed: () => _edit(isEvent: event),
              icon: const Icon(Icons.add),
              tooltip: event ? 'Add event' : 'Add task',
              style: IconButton.styleFrom(
                backgroundColor: studyBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          event
              ? 'Your exams, classes and everything ahead.'
              : 'One thing at a time. Make today count.',
          style: const TextStyle(color: studyMuted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: ValueKey('search-$event'),
          controller: _searchField,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: event ? 'Search events' : 'Search tasks',
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in [
                'All',
                'Today',
                'Upcoming',
                'Overdue',
                if (event) 'Completed',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: status == filter,
                    onSelected: (_) => setState(() {
                      if (event) {
                        eventStatus = filter;
                      } else {
                        taskStatus = filter;
                      }
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _filter(subject, [
              'All subjects',
              ...subjects,
            ], (v) => setState(() => subject = v)),
            _filter(
              dateFilter,
              ['Any date', 'Today', 'Next 7 days', 'Choose date'],
              (v) async {
                if (v == 'Choose date') {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: customDate ?? today,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (date != null && mounted) {
                    setState(() {
                      customDate = date;
                      dateFilter = v;
                    });
                  }
                } else {
                  setState(() {
                    dateFilter = v;
                    customDate = null;
                  });
                }
              },
            ),
            _filter(priority, [
              'Any priority',
              'Low',
              'Medium',
              'High',
            ], (v) => setState(() => priority = v)),
            if (event)
              _filter(eventType, [
                'All types',
                'Exam',
                'Assignment',
                'Class',
                'Meeting',
                'Personal',
                'Other',
              ], (v) => setState(() => eventType = v)),
          ],
        ),
        if (customDate != null)
          Text(
            dateLabel(customDate!, full: true),
            style: const TextStyle(color: studyBlue),
          ),
        _heading('${items.length} ${event ? 'EVENTS' : 'TASKS'}'),
        if (items.isEmpty)
          _empty(
            'No ${event ? 'events' : 'tasks'} here',
            'Add a new item or change your filters.',
          )
        else
          ...items.map(_item),
      ],
    );
  }

  Future<void> _addSubject() async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('New subject'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: 'Subject name',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty ||
                    store.subjects.any(
                      (s) => s.toLowerCase() == name.toLowerCase(),
                    )) {
                  update(
                    () => error = name.isEmpty
                        ? 'Enter a subject name.'
                        : 'This subject already exists.',
                  );
                  return;
                }
                Navigator.pop(context, name);
              },
              child: const Text('Create subject'),
            ),
          ],
        ),
      ),
    );
    if (result != null) await store.addSubject(result);
    // Wait for the closing dialog to stop using its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  Widget _profile() {
    final tasks = visible.where((i) => !i.isEvent).toList();
    final thisMonth = StudyStore.monthKey(_now);
    final doneThisMonth = store.monthlyProgress[thisMonth] ?? 0;
    final openThisMonth = tasks
        .where((i) => i.date.year == _now.year && i.date.month == _now.month)
        .length;
    final planned = doneThisMonth + openThisMonth;
    final earlier =
        store.monthlyProgress.entries
            .where((e) => e.key.compareTo(thisMonth) < 0)
            .toList()
          ..sort((a, b) => b.key.compareTo(a.key));
    String monthName(String key) {
      final parts = key.split('-');
      return '${months[int.parse(parts[1]) - 1]} ${parts[0]}';
    }

    // One pass for all subject counts, instead of a full scan per subject row.
    final perSubject = <String, int>{};
    for (final item in visible) {
      if (item.subject.isNotEmpty) {
        perSubject[item.subject] = (perSubject[item.subject] ?? 0) + 1;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Profile',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          widget.displayName ?? 'Your workspace',
          style: const TextStyle(color: studyMuted),
        ),
        const SizedBox(height: 24),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('My Subjects'),
              icon: Icon(Icons.menu_book_outlined),
            ),
            ButtonSegment(
              value: true,
              label: Text('Progress'),
              icon: Icon(Icons.bar_chart),
            ),
          ],
          selected: {showProgress},
          onSelectionChanged: (v) => setState(() => showProgress = v.first),
        ),
        const SizedBox(height: 24),
        if (showProgress) ...[
          const Text(
            'Progress',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Tasks you complete in ${months[_now.month - 1]}',
            style: const TextStyle(color: studyMuted),
          ),
          const SizedBox(height: 16),
          StudyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$doneThisMonth ${doneThisMonth == 1 ? 'task' : 'tasks'} '
                  'completed in ${months[_now.month - 1]}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: planned == 0 ? 0 : doneThisMonth / planned,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                Text(
                  '$openThisMonth still to do this month',
                  style: const TextStyle(color: studyMuted),
                ),
              ],
            ),
          ),
          if (earlier.isNotEmpty) ...[
            _heading('EARLIER MONTHS'),
            for (final entry in earlier)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StudyCard(
                  child: Row(
                    children: [
                      Expanded(child: Text(monthName(entry.key))),
                      Text(
                        '${entry.value} completed',
                        style: const TextStyle(color: studyBlue),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ] else ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'My Subjects',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _addSubject,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add subject'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (store.subjects.isEmpty)
            _empty(
              'No subjects added yet',
              'Add your first subject to organise your tasks and events.',
            ),
          for (final name in store.subjects)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StudyCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFE9F2FC),
                      child: Text(name[0].toUpperCase()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${perSubject[name] ?? 0} planned items',
                            style: const TextStyle(
                              fontSize: 12,
                              color: studyMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              await FirebaseAuth.instance.signOut();
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not sign out. Please try again.'),
                  ),
                );
              }
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Read the clock once; every row and cell below reuses these.
    _now = DateTime.now();
    _today = dayOnly(_now);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              // No ValueKey(tab): switching tabs updates the existing elements
              // in place instead of tearing down and rebuilding the subtree.
              // _navigate resets the scroll offset explicitly instead.
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
              children: [
                if (store.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MaterialBanner(
                      content: Text(store.error!),
                      actions: [
                        TextButton(
                          onPressed: store.retrySave,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                if (store.loading) const LinearProgressIndicator(),
                switch (tab) {
                  0 => _home(),
                  1 => _calendar(),
                  2 => _listing(true),
                  3 => _listing(false),
                  _ => _profile(),
                },
              ],
            ),
          ),
        ),
      ),
      // Only the calendar keeps a floating Add: it is the one page where the
      // new item could be either kind, and it targets the selected day.
      // Events and Tasks each add their own kind from the + in their header.
      floatingActionButton: tab == 1 && !store.loading
          ? FloatingActionButton.extended(
              onPressed: _add,
              backgroundColor: studyBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: tab,
        onDestinationSelected: _navigate,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE3F0FD),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_box_outlined),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
