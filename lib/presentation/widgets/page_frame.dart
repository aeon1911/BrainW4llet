import 'package:flutter/material.dart';

/// Coluna rolável com largura máxima, para celular e desktop.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: children,
          ),
        ),
      ),
    );
  }
}
