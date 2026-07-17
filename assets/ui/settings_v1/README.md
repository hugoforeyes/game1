# Settings UI v1

The visual direction and production component sheet were generated through the
project's logged-in `OpenAiExtension` (`provider: chatgpt`). Runtime textures are
text-free; Godot renders every English/Vietnamese label using bundled fonts.

Source artifacts and prompts:

- `SceneBuilder/outputs/settings_ui_kit/mockup_raw.png`
- `SceneBuilder/outputs/settings_ui_kit/components_raw.png`
- `SceneBuilder/outputs/settings_ui_kit/components_matted.png`
- `SceneBuilder/outputs/settings_ui_kit/*_prompt.txt`

Reproduction:

```text
cd SceneBuilder
.venv/bin/python tools/generate_settings_ui_assets.py --only mockup
.venv/bin/python tools/generate_settings_ui_assets.py --only components
.venv/bin/python tools/process_settings_ui_assets.py
```

Like Journey and Inventory, Settings lives on an identity-transform `CanvasLayer`
and uses native doubled geometry, so fonts render at viewport resolution without
inheriting StartScene's 2x transform. `row_*`, `slider_*`, selector, divider, and
`back_frame` additionally retain 2x raster density over those native Control
rectangles. This matches Inventory's high-density texture strategy and preserves
source detail when `canvas_items` stretches onto Retina/2x windows.
`top_crest.png` retains its full cleaned source crop. The processor uniformly
scales decorative end caps and only stretches each bar's straight center strip.
The slider artwork is drawn separately from its transparent `HSlider`, preserving
the original hitbox.
The large modal uses `UiKit.make_ornate_frame()` so its corners are nine-sliced
at a fixed optical size rather than stretched.
