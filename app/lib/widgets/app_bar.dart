import 'package:material_ui/material_ui.dart';
import 'package:tapdancer/utils/app_theme.dart';

class AppBarWidget extends StatefulWidget implements PreferredSizeWidget {
  final String title;

  /// Optional trailing actions shown on the right of the app bar.
  final List<Widget>? actions;

  const AppBarWidget({
    super.key,
    required this.title,
    this.actions,
  });

  @override
  State<AppBarWidget> createState() => _AppBarWidgetState();

  @override
  Size get preferredSize => const Size.fromHeight(AppColor.appBarHeight);
}

class _AppBarWidgetState extends State<AppBarWidget> {
  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: AppSizing.paddingXLarge,
      toolbarHeight: AppColor.appBarHeight,
      actions: widget.actions,
      title: Row(
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColor.textPrimary,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
