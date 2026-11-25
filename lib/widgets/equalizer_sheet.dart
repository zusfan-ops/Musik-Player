import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../theme/app_theme.dart';

class EqualizerSheet extends StatelessWidget {
  const EqualizerSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const EqualizerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final gains = provider.eqBandGains;
    final labels = provider.eqBandLabels;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.equalizer_rounded,
                  color: AppColors.spotifyGreen,
                  size: 24,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Equalizer 5-Band & Bass Boost',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Atur karakter suara & penguat volume',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: provider.equalizerEnabled,
                  onChanged: provider.setEqualizerEnabled,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Preset chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final preset in MusicProvider.eqPresets.keys)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(preset),
                        selected: provider.activeEqPreset == preset,
                        onSelected: (_) => provider.applyEqPreset(preset),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5-Band Vertical Sliders
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(gains.length, (i) {
                  final db = gains[i];
                  return Column(
                    children: [
                      Text(
                        '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: provider.equalizerEnabled
                              ? AppColors.spotifyGreen
                              : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(
                        height: 150,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value: db.clamp(
                              provider.eqMinDecibels,
                              provider.eqMaxDecibels,
                            ),
                            min: provider.eqMinDecibels,
                            max: provider.eqMaxDecibels,
                            onChanged: provider.equalizerEnabled
                                ? (val) => provider.setEqBandGain(i, val)
                                : null,
                          ),
                        ),
                      ),
                      Text(
                        i < labels.length ? labels[i] : 'B${i + 1}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),

            // Bass Boost & Loudness Enhancer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.speaker_rounded,
                        size: 18,
                        color: AppColors.neonCyan,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Bass Boost',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${(provider.bassBoostStrength * 100).round()}%',
                        style: const TextStyle(
                          color: AppColors.neonCyan,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: provider.bassBoostStrength,
                    min: 0.0,
                    max: 1.0,
                    activeColor: AppColors.neonCyan,
                    onChanged: provider.setBassBoost,
                  ),
                  const Divider(height: 12, color: AppColors.surfaceHighlight),
                  Row(
                    children: [
                      const Icon(
                        Icons.volume_up_rounded,
                        size: 18,
                        color: AppColors.spotifyGreen,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Loudness Enhancer',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '+${provider.loudnessGainDb.toStringAsFixed(1)} dB',
                        style: const TextStyle(
                          color: AppColors.spotifyGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: provider.loudnessGainDb,
                    min: 0.0,
                    max: 10.0,
                    onChanged: provider.setLoudnessGain,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await provider.applyEqPreset('Flat');
                    await provider.setBassBoost(0.0);
                    await provider.setLoudnessGain(0.0);
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset Flat'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
