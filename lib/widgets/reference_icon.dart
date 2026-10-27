import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The exact 24px paths used by the approved reference.
class ReferenceIcon extends StatelessWidget {
  const ReferenceIcon(this.name,
      {super.key, this.size = 20, this.color, this.filled = false});
  final String name;
  final double size;
  final Color? color;
  final bool filled;
  static const paths = <String, String>{
    'play': '<path d="m9 5 11 7-11 7z"/>',
    'pause': '<path d="M8 5v14M16 5v14"/>',
    'clock': '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3 2"/>',
    'numbered':
        '<path d="M10 6h10M10 12h10M10 18h10M4 4h1v5M3.5 13c0-2 3-2 3 0 0 1-3 2-3 4h3"/>',
    'home':
        '<path d="M4 10.5 12 4l8 6.5V20a1 1 0 0 1-1 1h-4.5v-6h-5v6H5a1 1 0 0 1-1-1z"/>',
    'notes':
        '<rect x="4" y="3.5" width="16" height="17" rx="3"/><path d="M8 8.5h8M8 12h8M8 15.5h5"/>',
    'star':
        '<path d="m12 3.8 2.5 5.1 5.6.8-4 3.9.9 5.6-5-2.6-5 2.6.9-5.6-4-3.9 5.6-.8z"/>',
    'people':
        '<circle cx="9" cy="8.5" r="3.5"/><path d="M2.5 20c.6-3.5 3.3-5.5 6.5-5.5s5.9 2 6.5 5.5"/><circle cx="17" cy="9" r="2.6"/><path d="M17 14.5c2.5 0 4.2 1.6 4.6 4.5"/>',
    'user':
        '<circle cx="12" cy="8.5" r="4"/><path d="M4.5 20.5c.8-4 3.8-6 7.5-6s6.7 2 7.5 6"/>',
    'search': '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
    'plus': '<path d="M12 5v14M5 12h14"/>',
    'back': '<path d="m15 5-7 7 7 7"/>',
    'next': '<path d="m9 5 7 7-7 7"/>',
    'more':
        '<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>',
    'bell':
        '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
    'grid':
        '<rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="7" height="7" rx="2"/><rect x="13" y="13" width="7" height="7" rx="2"/>',
    'list':
        '<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r=".8"/><circle cx="4.5" cy="12" r=".8"/><circle cx="4.5" cy="18" r=".8"/>',
    'sort':
        '<path d="M7 4v16M3.5 16.5 7 20l3.5-3.5M17 20V4M13.5 7.5 17 4l3.5 3.5"/>',
    'spark':
        '<path d="M12 3.5c.6 4.2 2.3 6 6.5 6.5-4.2.6-5.9 2.3-6.5 6.5-.6-4.2-2.3-5.9-6.5-6.5 4.2-.5 5.9-2.3 6.5-6.5z"/><path d="M18.5 16v4M16.5 18h4"/>',
    'share':
        '<path d="M12 15V4M8 7.5 12 4l4 3.5"/><path d="M5 12v6.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V12"/>',
    'check': '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    'x': '<path d="M6 6l12 12M18 6 6 18"/>',
    'moon': '<path d="M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z"/>',
    'sun':
        '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/>',
    'trash': '<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/>',
    'copy':
        '<rect x="8" y="8" width="12" height="12" rx="2.5"/><path d="M16 8V5.5A1.5 1.5 0 0 0 14.5 4h-9A1.5 1.5 0 0 0 4 5.5v9A1.5 1.5 0 0 0 5.5 16H8"/>',
    'mail':
        '<rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="m4 7 8 6 8-6"/>',
    'focus':
        '<path d="M4 9V5.5A1.5 1.5 0 0 1 5.5 4H9M15 4h3.5A1.5 1.5 0 0 1 20 5.5V9M20 15v3.5a1.5 1.5 0 0 1-1.5 1.5H15M9 20H5.5A1.5 1.5 0 0 1 4 18.5V15"/>',
    'arrow': '<path d="M5 12h14M13 6l6 6-6 6"/>',
    'doc':
        '<path d="M6.5 3.5h7l4 4v12a1 1 0 0 1-1 1h-10a1 1 0 0 1-1-1v-15a1 1 0 0 1 1-1z"/><path d="M13.5 3.5v4h4"/>',
    'cal':
        '<rect x="3.5" y="5" width="17" height="15.5" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
    'mic':
        '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
    'image':
        '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><circle cx="9" cy="10" r="1.6"/><path d="m4 17.5 5-4.5 4 3.5 2.5-2 4.5 3.5"/>',
    'pen':
        '<path d="M4 20c2-1 3.5-3 5-3s1.5 2 3.5 2 3-3 4.5-3 2 1 3 1.5"/><path d="m13.5 4.5 3 3L9 15l-3.5.5.5-3.5z"/>',
    'todo':
        '<rect x="3.5" y="4" width="6" height="6" rx="1.6"/><path d="m5 7 1.2 1.2L8.3 6M13 7h7.5M3.5 15.5h6M13 17h7.5"/><rect x="3.5" y="14" width="6" height="6" rx="1.6"/>',
    'type':
        '<path d="M4 18 8.5 6h1L14 18M5.6 14h6.8M15.5 13.5c.4-1.3 1.4-2 2.8-2 1.7 0 2.7 1 2.7 2.7V18M21 15.6c-.8-.4-1.7-.6-2.7-.6-1.6 0-2.8.8-2.8 1.8s.9 1.6 2 1.6c1.6 0 3.5-1 3.5-2.8"/>',
    'marker': '<path d="m14.5 4.5 5 5-8 8H7v-4.5z"/><path d="M4 20.5h16"/>',
    'bullets':
        '<circle cx="5" cy="7" r="1.2"/><circle cx="5" cy="12" r="1.2"/><circle cx="5" cy="17" r="1.2"/><path d="M9.5 7H20M9.5 12H20M9.5 17H20"/>',
    'alignC': '<path d="M4 6h16M7 10h10M4 14h16M7 18h10"/>',
    'alignR': '<path d="M4 6h16M10 10h10M4 14h16M10 18h10"/>',
    'link':
        '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    'live':
        '<circle cx="12" cy="12" r="2"/><path d="M8 8a5.6 5.6 0 0 0 0 8M16 8a5.6 5.6 0 0 1 0 8M5 5a10 10 0 0 0 0 14M19 5a10 10 0 0 1 0 14"/>',
    'eye':
        '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
    'edit': '<path d="m14.5 5.5 4 4L8 20H4v-4z"/>',
    'gear':
        '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    'history':
        '<path d="M3.5 12a8.5 8.5 0 1 0 2.5-6"/><path d="M3.5 4.5V9H8M12 7.5V12l3 2"/>',
    'up':
        '<path d="M7 10.5v9H4.5v-9zM7 10.5l4-7a2 2 0 0 1 2.5 2.3L13 9.5h5.3a2 2 0 0 1 2 2.4l-1.3 6a2 2 0 0 1-2 1.6H7"/>',
    'down':
        '<path d="M7 13.5v-9H4.5v9zM7 13.5l4 7a2 2 0 0 0 2.5-2.3L13 14.5h5.3a2 2 0 0 0 2-2.4l-1.3-6a2 2 0 0 0-2-1.6H7"/>',
    'refresh':
        '<path d="M20 11a8 8 0 0 0-14.5-4.5L4 8M4 4v4h4M4 13a8 8 0 0 0 14.5 4.5L20 16M20 20v-4h-4"/>',
    'cards':
        '<rect x="3.5" y="6.5" width="13" height="13" rx="2.5"/><path d="M8 3.5h10a2.5 2.5 0 0 1 2.5 2.5v10"/>',
    'layers':
        '<path d="m12 3.5 8.5 4.5-8.5 4.5L3.5 8z"/><path d="m3.5 12 8.5 4.5 8.5-4.5M3.5 16l8.5 4.5 8.5-4.5"/>',
    'bulb':
        '<path d="M9 17.5h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2V16h5v-.1c0-.8.4-1.5 1-2A6 6 0 0 0 12 3z"/>',
    'target':
        '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r=".8"/>',
    'lock':
        '<rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>',
    'download': '<path d="M12 4v11M8 11l4 4 4-4M5 19.5h14"/>',
    'stop': '<rect x="7" y="7" width="10" height="10" rx="2"/>',
    'help':
        '<circle cx="12" cy="12" r="8.5"/><path d="M9.7 9.5a2.4 2.4 0 0 1 4.6.8c0 1.6-2.3 2-2.3 3.5M12 16.8v.2"/>',
    'undo':
        '<path d="M9 7 4.5 11.5 9 16"/><path d="M5 11.5h9.5a5 5 0 0 1 0 10H12"/>',
  };
  @override
  Widget build(BuildContext context) {
    final ink = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final data =
        '<svg width="24" height="24" viewBox="0 0 24 24" fill="${filled ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${paths[name] ?? paths['notes']}</svg>';
    return ExcludeSemantics(
        child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: SizedBox.square(
                dimension: size,
                child: SvgPicture.string(data,
                    width: size,
                    height: size,
                    colorFilter: ColorFilter.mode(ink, BlendMode.srcIn)))));
  }
}
