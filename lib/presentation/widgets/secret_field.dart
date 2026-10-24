import 'package:flutter/material.dart';

/// Campo de texto para segredos: sem sugestões, autocorreção ou aprendizado
/// do teclado, oculto por padrão e fora do preenchimento automático.
class SecretField extends StatefulWidget {
  const SecretField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.textInputAction = TextInputAction.next,
    this.initiallyVisible = false,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputAction textInputAction;
  final bool initiallyVisible;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  late bool _visible = widget.initiallyVisible;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      // Campo oculto precisa ser de uma linha; visível pode quebrar.
      maxLines: _visible ? widget.maxLines : 1,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: null,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _visible ? 'Ocultar' : 'Mostrar',
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}
