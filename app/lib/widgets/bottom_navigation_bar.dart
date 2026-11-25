import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapdancer/utils/app_theme.dart';
import 'package:tapdancer/utils/firmware_info.dart';

class BottomNavigationBarWidget extends ConsumerStatefulWidget {
  final ValueChanged<int> onItemSelected;

  const BottomNavigationBarWidget({
    super.key,
    required this.onItemSelected,
  });

  @override
  ConsumerState<BottomNavigationBarWidget> createState() => _BottomNavigationBarWidgetState();
}

class _BottomNavigationBarWidgetState extends ConsumerState<BottomNavigationBarWidget> {
  int _currentIndex = 0;

  void _onTap(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
      widget.onItemSelected(index); // Notify parent
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateAvailable = ref.watch(firmwareUpdateAvailableProvider);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey, // Line color
            width: Platform.isWindows ? 0.5 : 0.0, // Thin line thickness
          ),
        ),
      ),
      child: Theme(
        // Suppress the white ink ripple/highlight that flashes on tap.
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTap,
          elevation: 8,
          enableFeedback: false,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.devices),
              label: 'Devices',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.tune),
              label: 'Button Configurations',
            ),
            BottomNavigationBarItem(
              // A small badge flags an available firmware update.
              icon: Badge(
                isLabelVisible: updateAvailable,
                backgroundColor: AppColor.warning,
                child: const Icon(Icons.settings),
              ),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
