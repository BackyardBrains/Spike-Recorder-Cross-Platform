import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
            color: const Color(0xFF2C2C2C), // Dark background
            borderRadius: BorderRadius.circular(20), // Highly rounded corners
            border: Border.all(
              color: Colors.white10, // Subtle grey/white border
              width: 1,
            ),
          ),
          child: Text("Choose the serial port device", style: TextStyle(color: Colors.white)),
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
          hint: Text(
            "NO DETECTED PORTS ${selectedValue ?? ""}",
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
            });
          },
        ),
      ),
    );
  }
}