import 'package:flutter/material.dart';

/// School/College toggle plus a required class or year dropdown. Reports a
/// label such as "Class 10" or "Year 2", which is what the profile stores.
/// Used on sign-up and on the page that asks for missing profile details.
class ClassPicker extends StatefulWidget {
  const ClassPicker({super.key, required this.onChanged, this.enabled = true});

  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  State<ClassPicker> createState() => _ClassPickerState();
}

class _ClassPickerState extends State<ClassPicker> {
  String _institution = 'School';
  String? _value;

  bool get _school => _institution == 'School';

  Widget _labelled(String label, Widget field) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        field,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _labelled(
        'I study at',
        SegmentedButton<String>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          segments: const [
            ButtonSegment(value: 'School', label: Text('School')),
            ButtonSegment(value: 'College', label: Text('College')),
          ],
          selected: {_institution},
          onSelectionChanged: widget.enabled
              ? (v) {
                  setState(() {
                    _institution = v.first;
                    _value = null;
                  });
                  widget.onChanged(null);
                }
              : null,
        ),
      ),
      _labelled(
        _school ? 'Class' : 'Year',
        DropdownButtonFormField<String>(
          key: ValueKey(_institution),
          initialValue: _value,
          hint: Text(_school ? 'Select class' : 'Select year'),
          items: [
            for (var i = 1; i <= (_school ? 12 : 6); i++)
              DropdownMenuItem(
                value: '${_school ? 'Class' : 'Year'} $i',
                child: Text('${_school ? 'Class' : 'Year'} $i'),
              ),
          ],
          validator: (v) =>
              v == null ? 'Choose your ${_school ? 'class' : 'year'}.' : null,
          onChanged: widget.enabled
              ? (v) {
                  setState(() => _value = v);
                  widget.onChanged(v);
                }
              : null,
        ),
      ),
    ],
  );
}
