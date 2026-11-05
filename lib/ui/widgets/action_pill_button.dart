import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../preference/user_preferences.dart';
import '../../util/focus/input_mode_tracker.dart';

/// The detail screen's secondary action button (Play / Delete / etc.), reused verbatim: a circular
/// icon that smoothly grows into a labeled pill on hover/focus (AnimatedContainer, 150ms easeOut) using
/// the app's own AppColorScheme tokens — NOT a bespoke colour. Lifted from _DetailActionButton's modern
/// landscape path so the picker / Regional buttons match the detail buttons exactly.
class ActionPillButton extends StatefulWidget {
  final IconData? icon;
  final Widget Function(double size, Color color)? iconBuilder;
  final String label;
  final VoidCallback onPressed;
  final double height;

  const ActionPillButton({
    super.key,
    this.icon,
    this.iconBuilder,
    required this.label,
    required this.onPressed,
    this.height = 46,
  });

  @override
  State<ActionPillButton> createState() => _ActionPillButtonState();
}

class _ActionPillButtonState extends State<ActionPillButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // Focus visuals only while keys drive (keyboard/TV); mouse uses hover — same rule as the detail button.
    final showHighlight =
        _hovered || InputModeTracker.showFocusVisuals(context, _focused);
    final focusColor = Color(
      GetIt.instance<UserPreferences>().get(UserPreferences.focusColor).colorValue,
    );
    final height = widget.height;
    final isExpanded = showHighlight;

    final containerColor = showHighlight
        ? AppColorScheme.buttonFocused
        : Colors.white.withValues(alpha: 0.06);
    final borderColor = showHighlight
        ? focusColor
        : AppColorScheme.onSurface.withValues(alpha: 0.35);
    final iconColor =
        showHighlight ? AppColorScheme.onButtonFocused : AppColorScheme.onButtonNormal;
    final labelColor = iconColor;

    final maxWidth = isExpanded ? 200.0 : height;
    final maxLabelWidth = (maxWidth -
            (isExpanded ? 22.0 : 0.0) -
            (showHighlight ? 5.0 : 3.0) -
            (height - 4) -
            6.0)
        .clamp(0.0, maxWidth);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            // Matches the TV app's `transition: 0.2s ease` (Flutter Curves.ease == CSS ease) so the
            // expand/collapse feels as smooth as the TV action buttons.
            duration: const Duration(milliseconds: 200),
            curve: Curves.ease,
            height: height,
            constraints: BoxConstraints(minWidth: height, maxWidth: maxWidth),
            padding: EdgeInsets.only(left: isExpanded ? 6 : 0, right: isExpanded ? 16 : 0),
            decoration: BoxDecoration(
              borderRadius: AppRadius.circular(height / 2),
              color: containerColor,
              border: Border.all(color: borderColor, width: showHighlight ? 2.5 : 1.5),
            ),
            child: ClipRRect(
              borderRadius: AppRadius.circular(height / 2),
              clipBehavior: Clip.hardEdge,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: height - 4,
                      child: Center(
                        child: widget.iconBuilder != null
                            ? widget.iconBuilder!(24, iconColor)
                            : Icon(widget.icon, size: 24, color: iconColor),
                      ),
                    ),
                    if (isExpanded && widget.label.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxLabelWidth),
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: labelColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    height: 1.1,
                                  ) ??
                              TextStyle(
                                  color: labelColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  height: 1.1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
