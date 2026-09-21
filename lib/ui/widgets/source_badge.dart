/// 源角标与源名映射
library;

import 'package:flutter/material.dart';

const Map<String, String> sourceNames = {
  'jm': 'JM',
  'pica': '哔咔',
  'eh': 'EH',
  'pixiv': 'Pixiv',
};

String sourceName(String key) => sourceNames[key] ?? key;

class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        sourceName(source),
        style: TextStyle(fontSize: 10, color: scheme.onSecondaryContainer),
      ),
    );
  }
}
