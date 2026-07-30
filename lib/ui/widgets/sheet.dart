/// The furniture every screen that is not the table is built from.
///
/// Setting up a game, joining one, signing in — none of them are part of the
/// Buraco Livre table design, so they all borrow the same sheet: a card of one
/// width, floated on the [Stage], with labelled fields stacked down it. Keeping
/// that in one place is what stops the fourth such screen from being the third
/// slightly different card.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The card every non-table screen sits on.
///
/// The width is fixed rather than proportional because the [Stage] already
/// scales the whole screen to fit — a card that also flexed would be scaled
/// twice.
class SheetCard extends StatelessWidget {
  final Palette palette;
  final List<Widget> children;
  final double width;

  const SheetCard({
    super.key,
    required this.palette,
    required this.children,
    this.width = 520,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      decoration: BoxDecoration(
        color: palette.sheet,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    ),
  );
}

/// The small mono caption over a field.
class FieldLabel extends StatelessWidget {
  final String label;
  final Palette palette;

  const FieldLabel({super.key, required this.label, required this.palette});

  @override
  Widget build(BuildContext context) =>
      Text(label, style: mono(10, color: palette.ashDim));
}

/// Segments sit 8px apart, always.
class ChoiceRow extends StatelessWidget {
  final List<Widget> children;

  const ChoiceRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        children[i],
      ],
    ],
  );
}

/// A labelled row of choices.
class ChoiceField extends StatelessWidget {
  final String label;
  final Palette palette;
  final List<Widget> children;

  const ChoiceField({
    super.key,
    required this.label,
    required this.palette,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(label: label, palette: palette),
      const SizedBox(height: 8),
      ChoiceRow(children: children),
    ],
  );
}

/// A labelled line of text the player types into.
class TextEntry extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final Palette palette;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  const TextEntry({
    super.key,
    required this.label,
    required this.controller,
    required this.palette,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label: label, palette: p),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          onSubmitted: onSubmitted,
          style: T.body(15, color: p.text),
          decoration: InputDecoration(
            filled: true,
            hintText: hint,
            hintStyle: T.body(15, color: p.ashDim),
            fillColor: p.panel,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.mint, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
