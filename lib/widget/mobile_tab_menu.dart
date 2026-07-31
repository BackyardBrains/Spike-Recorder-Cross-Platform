import 'package:flutter/material.dart';

class MenuControllerNotifier extends ValueNotifier<int> {
  MenuControllerNotifier(super.value);
}

class MobileTabMenu extends StatelessWidget {
  final MenuControllerNotifier controller;

  MobileTabMenu({
    super.key,
    required this.controller,
  });

  final List<MenuData> _menuItems = [
    MenuData(icon: Icons.play_arrow_outlined, label: 'View / Record'),
    MenuData(icon: Icons.timeline, label: 'Threshold'),
    MenuData(icon: Icons.folder_open_outlined, label: 'Recordings'),
  ];

  @override
  Widget build(BuildContext context) {
    const double barWidth = 360.0;
    const double barHeight = 60.0;
    final double itemWidth = barWidth / _menuItems.length;

    // ValueListenableBuilder listens to your controller changes and rebuilds only this block
    return ValueListenableBuilder<int>(
      valueListenable: controller,
      builder: (context, selectedIndex, child) {
        return Container(
          width: barWidth,
          height: barHeight,
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(30.0),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
              width: 1.0,
            ),
          ),
          child: Stack(
            children: [
              // Sliding active pill indicator
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                left: selectedIndex * (itemWidth - (8.0 / _menuItems.length)),
                child: Container(
                  width: itemWidth - 4.0,
                  height: barHeight - 10.0,
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(26.0),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                ),
              ),
              // Menu Options
              Row(
                children: List.generate(_menuItems.length, (index) {
                  final item = _menuItems[index];
                  final isSelected = selectedIndex == index;

                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => controller.value = index, // Updates the listener
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.icon,
                            color: isSelected ? Colors.white : Colors.grey,
                            size: 22,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected ? Colors.white : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MenuData {
  final IconData icon;
  final String label;

  MenuData({required this.icon, required this.label});
}