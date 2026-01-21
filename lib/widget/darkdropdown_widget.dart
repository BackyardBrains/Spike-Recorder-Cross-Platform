import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DarkDropdown extends StatefulWidget {
  const DarkDropdown({super.key});

  @override
  State<DarkDropdown> createState() => _DarkDropdownState();
}

class _DarkDropdownState extends State<DarkDropdown> {
  String? selectedValue;

  @override
  Widget build(BuildContext context) {
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
            "NO DETECTED PORTS",
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
          items: <String>['Port 1', 'Port 2', 'Port 3']
              .map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value, style: const TextStyle(color: Colors.white)),
            );
          }).toList(),
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