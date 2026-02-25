import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
            color: const Color(0xFF2C2C2C), // Dark background
            borderRadius: BorderRadius.circular(20), // Highly rounded corners
            border: Border.all(
              color: Colors.white10, // Subtle grey/white border
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              hint: const Text(
                "NO ITEMS",
                style: TextStyle(
                  color: Colors.white38, // Muted text color
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              dropdownColor: const Color(0xFF2C2C2C),
              // 2. Customizing the arrow icons to match your image
              icon: const Icon(
                Icons.unfold_more, // This gives the up/down arrow look
                color: Colors.white70,
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
        color: const Color(0xFF2C2C2C), // Dark background
        borderRadius: BorderRadius.circular(20), // Highly rounded corners
        border: Border.all(
          color: Colors.white10, // Subtle grey/white border
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedValue,
          hint: const Text(
            "NO ITEMS",
            style: TextStyle(
              color: Colors.white38, // Muted text color
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          dropdownColor: const Color(0xFF2C2C2C),
          // 2. Customizing the arrow icons to match your image
          icon: const Icon(
            Icons.unfold_more, // This gives the up/down arrow look
            color: Colors.white70,
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