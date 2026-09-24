import 'package:flutter/material.dart';

import '../../domain/models/models.dart';

/// Creates or edits a custom tag.
///
/// The category and seating hint are pickers rather than free text on purpose:
/// they are the structured part a future AI reads, while the label and
/// description are for the teacher.
class TagEditorDialog extends StatefulWidget {
  const TagEditorDialog({this.tag, super.key});

  final StudentTag? tag;

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late final _label = TextEditingController(text: widget.tag?.label ?? '');
  late final _description = TextEditingController(
    text: widget.tag?.description ?? '',
  );
  late TagCategory _category = widget.tag?.category ?? TagCategory.custom;
  late SeatingHint _hint = widget.tag?.hint ?? SeatingHint.none;
  late int _color = widget.tag?.colorValue ?? kGroupColors.first;

  @override
  void dispose() {
    _label.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.tag == null ? 'New tag' : 'Edit tag'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _label,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g. Talks a lot',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TagCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in TagCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SeatingHint>(
                initialValue: _hint,
                decoration: const InputDecoration(
                  labelText: 'Seating hint',
                  helperText: 'Used when shuffling, and later by AI',
                ),
                items: [
                  for (final h in SeatingHint.values)
                    DropdownMenuItem(value: h, child: Text(h.label)),
                ],
                onChanged: (v) => setState(() => _hint = v ?? _hint),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'What should someone know about this tag?',
                ),
              ),
              const SizedBox(height: 16),
              Text('Colour', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final color in kGroupColors)
                    InkWell(
                      onTap: () => setState(() => _color = color),
                      child: CircleAvatar(
                        backgroundColor: Color(color),
                        radius: 14,
                        child: _color == color
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = _label.text.trim();
            if (label.isEmpty) return;
            final existing = widget.tag;
            Navigator.of(context).pop(
              existing == null
                  ? StudentTag.create(
                      label: label,
                      category: _category,
                      hint: _hint,
                      description: _description.text.trim(),
                      colorValue: _color,
                    )
                  : existing.copyWith(
                      label: label,
                      category: _category,
                      hint: _hint,
                      description: _description.text.trim(),
                      colorValue: _color,
                    ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
