import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom navigation around the five main tabs (go_router StatefulShellRoute keeps each tab's state).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _titles = ['Nhập số', 'Nhập kết quả', 'Tính điểm', 'Khách hàng', 'Thêm'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[shell.currentIndex], style: const TextStyle(fontWeight: FontWeight.w700))),
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: 'Nhập số'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Kết quả'),
          NavigationDestination(icon: Icon(Icons.calculate_outlined), selectedIcon: Icon(Icons.calculate), label: 'Tính điểm'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Khách hàng'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Thêm'),
        ],
      ),
    );
  }
}
