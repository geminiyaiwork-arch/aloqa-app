/// ALOQA — labelled input matching the web `.input` (focus ring, prefix tint).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AloqaInput extends StatefulWidget {
  const AloqaInput({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.suffixIcon,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  State<AloqaInput> createState() => _AloqaInputState();
}

class _AloqaInputState extends State<AloqaInput> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() => setState(() => _focused = _node.hasFocus));
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.slate600)),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _focused
                ? [
                    BoxShadow(
                        color: AppColors.brand500.withOpacity(0.22),
                        spreadRadius: 3,
                        blurRadius: 0),
                  ]
                : const [],
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _node,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            validator: widget.validator,
            onChanged: widget.onChanged,
            textCapitalization: widget.textCapitalization,
            style: const TextStyle(fontSize: 15, color: AppColors.slate900),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: AppColors.slate400),
              prefixIcon: widget.prefixIcon == null
                  ? null
                  : Icon(widget.prefixIcon,
                      size: 20,
                      color: _focused ? AppColors.brand600 : AppColors.slate400),
              suffixIcon: widget.suffixIcon,
            ),
          ),
        ),
      ],
    );
  }
}
