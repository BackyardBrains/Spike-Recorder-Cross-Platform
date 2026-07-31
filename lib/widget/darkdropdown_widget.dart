import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/app_theme.dart';
import 'package:spikerbox_architecture/provider/theme_mode_provider.dart';

class DarkDropdown extends StatefulWidget {
  DarkDropdown({super.key, required this.kIsWeb, required this.availablePorts, required this.onPortSelected, required this.valueListenable});
  final bool kIsWeb;
  final List<String> availablePorts;
  String selectedValue = "";
  Function(String) onPortSelected;
  final ValueNotifier<String?> valueListenable;

  @override
  State<DarkDropdown> createState() => _DarkDropdownState();
}

class _DarkDropdownState extends State<DarkDropdown> {
  String? selectedValue;
  List<DropdownMenuItem<String>> dropdownItems = [];
  @override
  void initState() {
    super.initState();
    widget.valueListenable.removeListener(deviceListener);
    String? temp = widget.valueListenable.value;
    widget.valueListenable.value = "";
    widget.valueListenable.addListener(deviceListener);
    widget.valueListenable.value = temp;
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(deviceListener);
    super.dispose();
  }

  void deviceListener() {
    print("DARK deviceListener: ${widget.valueListenable.value}");
    if (mounted) {
      setState(() {
        dropdownItems.clear();
        // dropdownItems = widget.availablePorts.map((String value) {
        //   return DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(color: Colors.white)));
        // }).toList();
        if (widget.valueListenable.value != null) {
          dropdownItems.add(DropdownMenuItem<String>(value: widget.valueListenable.value, child: Text(widget.valueListenable.value ?? "", style: const TextStyle(color: Colors.white))));
          selectedValue = widget.valueListenable.value;          
        }
        // print("DEVICE dropdownItemsListener: $dropdownItems");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors =
        AppThemeColors.of(context.watch<ThemeModeProvider>().isDarkMode);
// widget.availablePorts}");
    if (widget.kIsWeb) {
      return GestureDetector(
        onTap: () {
          widget.onPortSelected(selectedValue ?? "");
        },
        child: Container(
          margin: const EdgeInsets.only(left: 0, right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: appColors.buttonBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: appColors.dropdownBorder,
              width: 1,
            ),
          ),
          child: Text("Choose the serial port device",
              style: TextStyle(color: appColors.textPrimary)),
        ),
      );
    }
    
    return Container(
      // 1. Styling the outer box
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: appColors.buttonBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: appColors.dropdownBorder,
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // DropdownButtonHideUnderline(
          //   child: DropdownButton<String>(
          //     value: selectedValue,
          //     hint: Text(
          //       selectedValue ?? "NO DETECTED PORTS",
          //       style: TextStyle(
          //         color: appColors.dropdownHint,
          //         fontWeight: FontWeight.bold,
          //         fontSize: 14,
          //         letterSpacing: 0.5,
          //       ),
          //     ),
          //     dropdownColor: appColors.buttonBackground,
          //     // icon: Icon(
          //     //   Icons.close,
          //     //   color: appColors.textPrimary.withOpacity(0.7),
          //     //   size: 20,
          //     // ),
          //     isExpanded: true, // Takes up full container width
          //     items: dropdownItems,
          //     // items: widget.availablePorts
          //     //     .map((String value) {
          //     //   return DropdownMenuItem<String>(
          //     //     value: value,
          //     //     child: Text(value, style: const TextStyle(color: Colors.white)),
          //     //   );
          //     // }).toList(),
          //     onChanged: (newValue) {
          //       // setState(() {
          //       //  selectedValue = newValue;
          //       // });
          //     },
          //     onTap: () {
          //       selectedValue = "";
          //       setState(() {});
          //       // print("ONTAP selectedValue: $selectedValue");
          //     },
          //   ),
          // ),
          Text(selectedValue ?? "NO DETECTED PORTS"),
          Positioned(
            right:0,
            top:0,
            child: GestureDetector(
              onTap: () {
                selectedValue = null;
                setState(() {});
                // print("ONTAP selectedValue: $selectedValue");
              },
              child: Icon(
                Icons.close,
                color: appColors.textPrimary.withOpacity(0.7),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}