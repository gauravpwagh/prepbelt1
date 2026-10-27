import 'package:flutter/material.dart';

import '../../../application/explain_due.dart';
import '../../../core/format.dart';

/// "Why is this due?" (CUJ 6): the stored explanation plus the exam cap.
class WhyDuePanel extends StatelessWidget {
  const WhyDuePanel(this.explanation, {super.key});
  final DueExplanation explanation;

  @override
  Widget build(BuildContext context) {
    final d = explanation.deadline;
    return Card(
      child: ExpansionTile(
        key: const Key('why-due'),
        title: const Text('Why is this due?'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(explanation.text),
          if (d != null) ...[
            const SizedBox(height: 8),
            Text('Next exam for this subject: ${d.examName} on ${formatShortDate(d.date)}.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
