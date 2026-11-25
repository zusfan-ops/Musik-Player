import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Smooth animated audio waveform visualizer bar synced to playback state.
class AudioWaveformVisualizer extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final int barCount;
  final double height;

  const AudioWaveformVisualizer({
    super.key,
    required this.isPlaying,
    this.color = AppColors.spotifyGreen,
    this.barCount = 28,
    this.height = 32,
  });

  @override
  State<AudioWaveformVisualizer> createState() =>
      _AudioWaveformVisualizerState();
}

class _AudioWaveformVisualizerState extends State<AudioWaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AudioWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) {
          final phase = _controller.value * 2 * math.pi;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.barCount, (i) {
              final norm = i / math.max(1, widget.barCount - 1);
              final envelope = math.sin(norm * math.pi);
              final wave = widget.isPlaying
                  ? 0.25 +
                      0.75 *
                          (0.5 +
                              0.5 *
                                  math.sin(
                                    phase * 2 +
                                        i * 0.65 +
                                        math.cos(phase + i * 0.35),
                                  ))
                  : 0.16;
              final barH = (widget.height *
                      (0.16 + wave * (0.45 + 0.55 * envelope)))
                  .clamp(4.0, widget.height);
              return Container(
                width: 3.2,
                height: barH,
                decoration: BoxDecoration(
                  color: widget.isPlaying
                      ? widget.color.withValues(
                          alpha: 0.55 + 0.45 * envelope,
                        )
                      : widget.color.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
