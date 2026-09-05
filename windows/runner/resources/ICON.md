# Application and tray icon

Created with the built-in `image_gen` tool. The selected source is `app_icon.png`.
The same mark is embedded in the executable and bundled as a Flutter asset for
the `tray_manager` tray icon.
`app_icon.ico` contains 32-bit PNG frames at 16, 20, 24, 32, 40, 48, 64, 128 and
256 pixels. `tool/convert_icon.ps1` performs only resizing and ICO encoding.

Final image prompt:

> Finalize this icon for Windows as an OPAQUE edge-to-edge square icon. Keep the
> two white and lavender overlapping chat bubbles and purple message bars exactly
> as the central mark. Remove ALL gray/white checkerboard around the tile and fill
> those areas with the same rich purple gradient as the tile, so the entire square
> canvas is the purple icon background from edge to edge and corner to corner.
> There must be NO checkerboard, NO transparent background, NO external margins
> and NO white border anywhere. A clean fully opaque purple square with the bold
> white/lavender chat mark centered, ready for small Windows ICO conversion. Flat
> clean professional look. Preserve the simplicity and broad shapes; no new
> elements, no controller, no text.
