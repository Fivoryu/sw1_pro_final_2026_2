import 'package:flutter/material.dart';

void main() {
  runApp(const RoomForgeApp());
}

class RoomForgeApp extends StatelessWidget {
  const RoomForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoomForge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
        ),
        useMaterial3: true,
      ),
      home: const CatalogPendingScreen(),
    );
  }
}

class CatalogPendingScreen extends StatelessWidget {
  const CatalogPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('RoomForge')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              color: colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.apartment_outlined,
                        size: 40,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Catálogo pendiente de integración',
                      style: textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'La aplicación todavía no está conectada a un catálogo '
                      'de inmuebles.',
                      style: textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
