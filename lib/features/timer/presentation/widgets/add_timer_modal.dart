import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';
import 'package:recipe_app/features/timer/presentation/providers/timer_providers.dart';
import 'package:recipe_app/features/settings/presentation/providers/settings_providers.dart';
import 'package:recipe_app/shared/widgets/sound_preview_button.dart';

class AddTimerModal extends ConsumerStatefulWidget {
  const AddTimerModal({super.key});

  @override
  ConsumerState<AddTimerModal> createState() => _AddTimerModalState();
}

class _AddTimerModalState extends ConsumerState<AddTimerModal> {
  int _minutes = 0;
  int _seconds = 0;
  final _labelController = TextEditingController();
  int? _selectedPreset;
  String _selectedSound = 'audio/Helium.mp3';

  static const _presets = [
    (30, '30s', false),
    (60, '1m', true),
    (180, '3m', true),
    (300, '5m', true),
    (600, '10m', true),
    (900, '15m', true),
    (1800, '30m', true),
    (3600, '60m', true),
  ];

  @override
  void initState() {
    super.initState();
    _selectedSound = ref.read(settingsProvider).defaultTimerSound;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  int get _totalSeconds => _minutes * 60 + _seconds;

  void _setPreset(int seconds) {
    setState(() {
      _selectedPreset = seconds;
      _minutes = seconds ~/ 60;
      _seconds = seconds % 60;
    });
  }

  void _start() {
    final seconds = _totalSeconds;
    if (seconds < 1) return;
    final label = _labelController.text.trim();
    ref.read(timerListProvider.notifier).addTimer(
      seconds,
      label: label.isNotEmpty ? label : null,
      soundFile: _selectedSound,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('New Timer', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Text('Quick presets', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: _presets.map((p) {
                final (seconds, label, _) = p;
                final selected = _selectedPreset == seconds;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => _setPreset(seconds),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Custom duration', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _DurationField(
                  label: 'min',
                  value: _minutes,
                  onChanged: (v) => setState(() {
                    _minutes = v.clamp(0, 999);
                    _selectedPreset = null;
                  }),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':'),
                ),
                _DurationField(
                  label: 'sec',
                  value: _seconds,
                  onChanged: (v) => setState(() {
                    _seconds = v.clamp(0, 59);
                    _selectedPreset = null;
                  }),
                  max: 59,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Icon(Icons.music_note_outlined, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedSound,
                    decoration: InputDecoration(
                      labelText: 'Alarm sound',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      isDense: true,
                    ),
                    items: kTimerSounds.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(soundDisplayName(s)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedSound = v);
                    },
                  ),
                ),
                SoundPreviewButton(soundFile: _selectedSound),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _labelController,
              decoration: InputDecoration(
                hintText: 'Label (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _totalSeconds > 0 ? _start : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  _totalSeconds > 0
                      ? 'Start ${_formatTotal(_totalSeconds)}'
                      : 'Set duration',
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  String _formatTotal(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0 && s > 0) return '${m}m ${s}s';
    if (m > 0) return '${m}m';
    return '${s}s';
  }
}

class _DurationField extends StatefulWidget {
  final String label;
  final int value;
  final int? max;
  final ValueChanged<int> onChanged;

  const _DurationField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max,
  });

  @override
  State<_DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<_DurationField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value.toString().padLeft(2, '0'),
    );
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      final focused = _focusNode.hasFocus;
      setState(() => _focused = focused);
      if (!focused) _submitText();
    });
  }

  @override
  void didUpdateWidget(_DurationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focused) {
      _controller.text = widget.value.toString().padLeft(2, '0');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submitText() {
    final parsed = int.tryParse(_controller.text);
    if (parsed != null) {
      final clamped = parsed.clamp(0, widget.max ?? 999);
      widget.onChanged(clamped);
      _controller.text = clamped.toString().padLeft(2, '0');
    } else {
      _controller.text = widget.value.toString().padLeft(2, '0');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => widget.onChanged((widget.value - 1).clamp(0, widget.max ?? 999)),
                  child: Icon(Icons.remove, size: 20,
                      color: theme.colorScheme.onSurface),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 40,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _submitText(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                GestureDetector(
                  onTap: () => widget.onChanged((widget.value + 1).clamp(0, widget.max ?? 999)),
                  child: Icon(Icons.add, size: 20,
                      color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(widget.label, style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )),
        ],
      ),
    );
  }
}
