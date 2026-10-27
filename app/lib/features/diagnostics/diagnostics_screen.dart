import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diagnostics_providers.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final integrity = ref.watch(integrityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.storage),
          title: const Text('Database integrity'),
          subtitle: Text(switch (integrity) {
            AsyncData(:final value) => '$value',
            AsyncError(:final error) => 'Check failed: $error',
            _ => 'Checking…',
          }),
          trailing: IconButton(
            tooltip: 'Check again',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(integrityProvider),
          ),
        ),
      ]),
    );
  }
}
