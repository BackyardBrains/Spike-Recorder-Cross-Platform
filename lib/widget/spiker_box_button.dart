import 'package:flutter/material.dart';
import 'package:spikerbox_architecture/constant/colors_constant.dart';

class SpikerBoxButton extends StatelessWidget {
  const SpikerBoxButton(
      {super.key,
      required this.onTapButton,
      this.iconSize,
      this.padding,
      this.iconColor,
      required this.iconData});
  final Function() onTapButton;
  final IconData iconData;
  final EdgeInsetsGeometry? padding;
  final Color? iconColor;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTapButton,
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
            color: iconColor ?? SoftwareColors.kButtonColor,
          ),
        ),
      ),
    );
  }
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
