import 'package:flutter/material.dart';
import 'package:spikerbox_architecture/constant/const_export.dart';

class WhiteColorCheckBox extends StatefulWidget {
  WhiteColorCheckBox({
    super.key,
    required this.onChanged,
    required this.valueStatus,
  });

  bool? valueStatus;
  final Function(bool?) onChanged;

  @override
  State<WhiteColorCheckBox> createState() => _WhiteColorCheckBoxState();
}

class _WhiteColorCheckBoxState extends State<WhiteColorCheckBox> {
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(unselectedWidgetColor: Colors.white),
      child: Checkbox(
        activeColor: SoftwareColors.kGraphColor,
        checkColor: Colors.white,
        onChanged: widget.onChanged,
        value: widget.valueStatus,
      ),
    );
  }
}
