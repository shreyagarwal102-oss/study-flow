import 'package:flutter/material.dart';
import '../study_store.dart';
import '../study_theme.dart';

class ItemEditor extends StatefulWidget {
  const ItemEditor({
    super.key,
    this.item,
    required this.isEvent,
    required this.date,
    required this.subjects,
  });
  final StudyItem? item;
  final bool isEvent;
  final DateTime date;
  final List<String> subjects;
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title = TextEditingController(
    text: widget.item?.title,
  );
  late final TextEditingController description = TextEditingController(
    text: widget.item?.description,
  );
  late final TextEditingController subject = TextEditingController(
    text: widget.item?.subject,
  );
  late DateTime date = dayOnly(widget.item?.date ?? widget.date);
  late TimeOfDay? time = widget.item?.hasTime == true
      ? TimeOfDay.fromDateTime(widget.item!.date)
      : null;
  late TimeOfDay? end = widget.item?.endTime == null
      ? null
      : TimeOfDay.fromDateTime(widget.item!.endTime!);
  late String priority = widget.item?.priority ?? 'Medium';
  late String type = widget.item?.type ?? (widget.isEvent ? 'Exam' : 'Task');
  String? timeError;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    subject.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool ending) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (ending ? end : time) ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() {
        if (ending) {
          end = picked;
        } else {
          time = picked;
        }
        timeError = null;
      });
    }
  }

  void _save() {
    if (!form.currentState!.validate()) return;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    final finish = end == null
        ? null
        : DateTime(date.year, date.month, date.day, end!.hour, end!.minute);
    if (finish != null && (time == null || !finish.isAfter(start))) {
      setState(
        () => timeError = 'Choose a start time and an end time after it.',
      );
      return;
    }
    Navigator.pop(
      context,
      StudyItem(
        id: widget.item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: title.text.trim(),
        date: start,
        isEvent: widget.isEvent,
        hasTime: time != null,
        completed: widget.item?.completed ?? false,
        subject: subject.text.trim(),
        priority: priority,
        type: type,
        description: description.text.trim(),
        endTime: finish,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.item == null ? 'New' : 'Edit'} ${widget.isEvent ? 'event' : 'task'}',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: title,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Title *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a title.' : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null && mounted) {
                      setState(() => date = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(dateLabel(date, full: true)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(false),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(time?.format(context) ?? 'Time (optional)'),
                      ),
                    ),
                    if (time != null)
                      IconButton(
                        tooltip: 'Clear time',
                        onPressed: () => setState(() {
                          time = null;
                          end = null;
                        }),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                if (widget.isEvent) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickTime(true),
                          child: Text(
                            end == null
                                ? 'End time (optional)'
                                : 'Ends ${end!.format(context)}',
                          ),
                        ),
                      ),
                      if (end != null)
                        IconButton(
                          tooltip: 'Clear end time',
                          onPressed: () => setState(() => end = null),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ],
                if (timeError != null)
                  Text(
                    timeError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 20),
                StudyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Details',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      if (widget.isEvent) ...[
                        DropdownButtonFormField<String>(
                          initialValue: type,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items:
                              [
                                    'Exam',
                                    'Assignment',
                                    'Class',
                                    'Meeting',
                                    'Personal',
                                    'Other',
                                  ]
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setState(() => type = v!),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: subject,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Subject (optional)',
                          hintText: 'e.g. Mathematics',
                        ),
                      ),
                      if (widget.subjects.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final name in widget.subjects)
                              ActionChip(
                                label: Text(name),
                                onPressed: () =>
                                    setState(() => subject.text = name),
                              ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: ['Low', 'Medium', 'High']
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => priority = v!),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: description,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Saved on this device. Your item also appears in Calendar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: studyMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: FilledButton(
          onPressed: _save,
          child: Text('Save ${widget.isEvent ? 'event' : 'task'}'),
        ),
      ),
    ),
  );
}
