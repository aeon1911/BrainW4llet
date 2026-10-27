import 'package:flutter/material.dart';

/// Coluna rolável com largura máxima, para celular e desktop.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.children, this.maxWidth = 600});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: children,
          ),
        ),
      ),
    );
  }
}
