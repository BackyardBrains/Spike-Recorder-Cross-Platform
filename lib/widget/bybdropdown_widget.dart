import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/app_theme.dart';
import 'package:spikerbox_architecture/provider/theme_mode_provider.dart';

class BybDropdown extends StatefulWidget {
  BybDropdown({super.key, required this.kIsWeb, required this.availableItems, required this.onItemSelected, required this.valueListenable});
  final bool kIsWeb;
  final List<String> availableItems;
  String selectedValue = "";
  Function(String) onItemSelected;
  final ValueNotifier<String?> valueListenable;

  @override
  State<BybDropdown> createState() => _BybDropdownState();
}

class _BybDropdownState extends State<BybDropdown> {
  String? selectedValue;
  List<DropdownMenuItem<String>> dropdownItems = [];

  @override
  void initState() {
    super.initState();
    dropdownItems.clear();
    // dropdownItems = widget.availablePorts.map((String value) {
    //   return DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(color: Colors.white)));
    // }).toList();
    selectedValue = widget.valueListenable.value;
    print("widget.availableItens: ${widget.availableItems}");
    for (var arr in widget.availableItems) {
      dropdownItems.add(DropdownMenuItem<String>(value: arr, child: Text(arr, style: const TextStyle(color: Colors.white))));

    }
    // widget.availableItems.map((arr) {
    //   print("widget.availableItems: ${widget.availableItems}");
    //   dropdownItems.add(DropdownMenuItem<String>(value: arr, child: Text(arr, style: const TextStyle(color: Colors.white))));

    // });
    print("dropdownItemsListener: ${dropdownItems}");

    // widget.valueListenable.removeListener(deviceListener);
    // widget.valueListenable.addListener(deviceListener);
  }

  @override
  void dispose() {
    // widget.valueListenable.removeListener(deviceListener);
    super.dispose();
  }

  void deviceListener() {
    print("deviceListener: ${widget.valueListenable.value}");
    if (mounted) {
      setState(() {
        dropdownItems.clear();
        // dropdownItems = widget.availablePorts.map((String value) {
        //   return DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(color: Colors.white)));
        // }).toList();
        widget.availableItems.map((arr) {
          print("widget.availableItems: ${widget.availableItems}");
          dropdownItems.add(DropdownMenuItem<String>(value: arr, child: Text(arr, style: const TextStyle(color: Colors.white))));

        });
        print("dropdownItemsListener: ${dropdownItems}");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors =
        AppThemeColors.of(context.watch<ThemeModeProvider>().isDarkMode);
    dropdownItems = widget.availableItems
        .map((arr) => DropdownMenuItem<String>(
              value: arr,
              child: Text(arr, style: TextStyle(color: appColors.textPrimary)),
            ))
        .toList();
// widget.availablePorts}");
    if (widget.kIsWeb) {
      return GestureDetector(
        onTap: () {
          widget.onItemSelected(selectedValue ?? "");
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
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              hint: Text(
                "NO ITEMS",
                style: TextStyle(
                  color: appColors.dropdownHint,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              dropdownColor: appColors.buttonBackground,
              icon: Icon(
                Icons.unfold_more,
                color: appColors.textPrimary.withOpacity(0.7),
                size: 20,
              ),
              isExpanded: true, // Takes up full container width
              items: dropdownItems,
              // items: widget.availablePorts
              //     .map((String value) {
              //   return DropdownMenuItem<String>(
              //     value: value,
              //     child: Text(value, style: const TextStyle(color: Colors.white)),
              //   );
              // }).toList(),
              onChanged: (newValue) {
                setState(() {
                  selectedValue = newValue;
                  widget.onItemSelected(selectedValue ?? "");
                });
              },
            ),
          ),
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
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedValue,
          hint: Text(
            "NO ITEMS",
            style: TextStyle(
              color: appColors.dropdownHint,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          dropdownColor: appColors.buttonBackground,
          icon: Icon(
            Icons.unfold_more,
            color: appColors.textPrimary.withOpacity(0.7),
            size: 20,
          ),
          isExpanded: true, // Takes up full container width
          items: dropdownItems,
          // items: widget.availablePorts
          //     .map((String value) {
          //   return DropdownMenuItem<String>(
          //     value: value,
          //     child: Text(value, style: const TextStyle(color: Colors.white)),
          //   );
          // }).toList(),
          onChanged: (newValue) {
            setState(() {
              selectedValue = newValue;
              widget.onItemSelected(selectedValue ?? "");
            });
          },
        ),
      ),
    );
  }
}