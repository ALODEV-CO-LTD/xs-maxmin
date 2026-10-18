import 'package:flutter/material.dart';

/// The one dropdown field of the app: a [DropdownButtonFormField] with the shared look - regular 16pt text, a rounded white list that is at most
/// 320 high (it scrolls) instead of a Material default list as tall as the screen, shown under the field.
class AppDropdown<T> extends DropdownButtonFormField<T> {
  AppDropdown({
    super.key,
    super.initialValue,
    required super.items,
    required super.onChanged,
    super.decoration,
    super.isExpanded,
    super.hint,
  }) : super(
         menuMaxHeight: 320,
         borderRadius: const BorderRadius.all(Radius.circular(12)),
         style: const TextStyle(
           fontSize: 15,
           fontWeight: FontWeight.w400,
           color: Colors.black,
         ),
       );
}
