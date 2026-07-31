import 'package:flutter/material.dart';
import 'package:spikerbox_architecture/constant/colors_constant.dart';

class SpikerBoxButton extends StatelessWidget {
  const SpikerBoxButton(
      {super.key,
      required this.onTapButton,
      this.iconSize,
      this.padding,
      this.iconColor,
      this.enabled = true,
      required this.iconData});
  final Function() onTapButton;
  final IconData iconData;
  final EdgeInsetsGeometry? padding;
  final Color? iconColor;
  final double? iconSize;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color resolvedIconColor = iconColor ?? SoftwareColors.kButtonColor;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTapButton : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: SoftwareColors.kButtonBackGroundColor,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(12.0),
            child: Icon(
              iconData,
              size: iconSize ?? 25,
              color: resolvedIconColor,
            ),
          ),
        ),
      ),
    );
  }
}

generateSpikerBoxDecorate(iconData) {
  Container boxStyle = Container(
    width: 50,
    height: 50,
    decoration: BoxDecoration(
      color: SoftwareColors.kButtonBackGroundColor,
      shape: BoxShape.circle,
    ),
    child: Padding(
      padding: const EdgeInsets.all(12.0),
      child: iconData,
    ),
  );
  return boxStyle;
}

// InkWell(
//       onTap: ontap,
//       child: DecoratedBox(
//         decoration: BoxDecoration(
//           color: SoftwareColors.kButtonBackGroundColor,
//           shape: BoxShape.circle,
//         ),
//         child: Padding(
//           padding: padding ?? const EdgeInsets.all(12.0),
//           child: Icon(
//             iconData,
//             size: padding != null ? 28 : 35,
//             color: SoftwareColors.kButtonColor,
//           ),
//         ),
//       ),
//     );
