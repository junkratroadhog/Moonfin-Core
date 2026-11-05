import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The EXACT icon artwork from the TV app's detail-action buttons, lifted verbatim
/// from `tv-client/packages/app/src/views/Details/detailIcons.js`. These are Material
/// Symbols glyphs authored on a `0 -960 960 960` viewBox, so the web/Flutter action
/// buttons render the IDENTICAL icons as the LG TV app rather than Material-font
/// look-alikes (`Icons.play_arrow`, `Icons.delete_outline`, …). The TV app is the
/// UI/UX source of truth; mirror its paths, do not substitute.
class DetailIconPaths {
  DetailIconPaths._();

  static const String download =
      'M480-320 280-520l56-58 104 104v-326h80v326l104-104 56 58-200 200ZM240-160q-33 0-56.5-23.5T160-240v-120h80v120h480v-120h80v120q0 33-23.5 56.5T800-160H240Z';
  static const String play = 'M320-200v-560l440 280-440 280Z';
  static const String delete =
      'M280-120q-33 0-56.5-23.5T200-200v-520h-40v-80h200v-40h240v40h200v80h-40v520q0 33-23.5 56.5T700-120H280Zm400-600H280v520h400v-520ZM360-280h80v-360h-80v360Zm160 0h80v-360h-80v360ZM280-720v520-520Z';
  static const String cancelRequest =
      'm256-200-56-56 224-224-224-224 56-56 224 224 224-224 56 56-224 224 224 224-56 56-224-224-224 224Z';
  static const String restart =
      'M480-80q-75 0-140.5-28.5t-114-77q-48.5-48.5-77-114T120-440h80q0 117 81.5 198.5T480-160q117 0 198.5-81.5T760-440q0-117-81.5-198.5T480-720h-6l62 62-56 58-160-160 160-160 56 58-62 62h6q75 0 140.5 28.5t114 77q48.5 48.5 77 114T840-440q0 75-28.5 140.5t-77 114q-48.5 48.5-114 77T480-80Z';
}

/// The TV picker's own inline `ICON` set (`SelectTorrentPopup.js`), authored on a
/// classic `0 0 24 24` viewBox — distinct from the detail-action Material Symbols
/// above. These power the picker chrome (header Refresh / Close). Pass
/// [PickerChromeIconPaths.viewBox] to [DetailGlyph] so they render at the right scale.
class PickerChromeIconPaths {
  PickerChromeIconPaths._();

  static const String viewBox = '0 0 24 24';
  static const String refresh =
      'M12 6v3l4-4-4-4v3c-4.42 0-8 3.58-8 8 0 1.57.46 3.03 1.24 4.26L6.7 14.8c-.45-.83-.7-1.79-.7-2.8 0-3.31 2.69-6 6-6zm6.76 1.74L17.3 9.2c.44.84.7 1.79.7 2.8 0 3.31-2.69 6-6 6v-3l-4 4 4 4v-3c4.42 0 8-3.58 8-8 0-1.57-.46-3.03-1.24-4.26z';
  static const String close =
      'M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z';
  static const String search =
      'M15.5 14h-.79l-.28-.27a6.5 6.5 0 10-.7.7l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0A4.5 4.5 0 1114 9.5 4.5 4.5 0 019.5 14z';
  static const String down =
      'M20 12l-1.41-1.41L13 16.17V4h-2v12.17l-5.58-5.59L4 12l8 8 8-8z';
  static const String up =
      'M4 12l1.41 1.41L11 7.83V20h2V7.83l5.58 5.59L20 12l-8-8-8 8z';
  static const String seed = 'M7 14l5-5 5z';
}

/// Mirror of the TV's `iconViewBox()` (components/icons/iconViewBox.js): every glyph
/// defaults to `0 -960 960 960`; a few off-centre ones are shifted by a measured
/// amount so they sit centred in a round button. Of the picker glyphs only `restart`
/// is corrected — by (0, -20) → `0 -980 960 960`.
String _viewBoxFor(String path) =>
    path == DetailIconPaths.restart ? '0 -980 960 960' : '0 -960 960 960';

/// Renders a TV icon [path] at [size], tinted [color]. Drop-in replacement for
/// `Icon(...)` — pass to `ActionPillButton.iconBuilder` so the button shows the TV's
/// exact glyph. Detail-action glyphs auto-resolve their `0 -960 960 960` viewBox; for
/// the `0 0 24 24` picker-chrome glyphs pass [viewBox] = [PickerChromeIconPaths.viewBox].
/// Uses `flutter_svg` (already a dependency) with a `srcIn` colour filter so the glyph
/// adopts the button's focus/normal icon colour.
class DetailGlyph extends StatelessWidget {
  final String path;
  final double size;
  final Color color;
  final String? viewBox;

  const DetailGlyph(this.path,
      {super.key, this.size = 24, required this.color, this.viewBox});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox ?? _viewBoxFor(path)}"><path d="$path"/></svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
