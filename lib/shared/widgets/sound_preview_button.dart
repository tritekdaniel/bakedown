import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class SoundPreviewButton extends StatefulWidget {
  final String soundFile;

  const SoundPreviewButton({super.key, required this.soundFile});

  @override
  State<SoundPreviewButton> createState() => _SoundPreviewButtonState();
}

class _SoundPreviewButtonState extends State<SoundPreviewButton> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _playing = false);
      });
    });
  }

  @override
  void didUpdateWidget(SoundPreviewButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.soundFile != widget.soundFile && _playing) {
      _player.stop();
      _playing = false;
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_playing) {
      _player.stop();
      setState(() => _playing = false);
    } else {
      _player.play(AssetSource(widget.soundFile));
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_playing ? Icons.stop : Icons.play_arrow, size: 20),
      tooltip: _playing ? 'Stop' : 'Preview',
      onPressed: _toggle,
      visualDensity: VisualDensity.compact,
    );
  }
}
