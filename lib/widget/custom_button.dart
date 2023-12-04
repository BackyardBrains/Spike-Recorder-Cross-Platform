import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final GestureTapCallback? onTap;
  final Color? colors;
  final Widget childWidget;
  final double? radius;
  final double? elevation;

  const CustomButton({
    super.key,
    required this.childWidget,
    this.onTap,
    this.colors,
    this.radius,
    this.elevation,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: RawMaterialButton(
        fillColor: colors,
        onPressed: onTap,
        splashColor: Colors.black12,
        elevation: elevation ?? 2.0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius ?? 32),
            side: const BorderSide(width: 2, color: Colors.grey)),
        child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 25.0, vertical: 10.0),
            child: childWidget),
      ),
    );
  }
}
