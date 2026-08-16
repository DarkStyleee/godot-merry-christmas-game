# Генерация полного набора ассетов. Запускать из корня проекта.
# Долгая: ~13 картинок по 40-60 с.
$root = Split-Path $PSScriptRoot -Parent
$raw  = Join-Path $root "assets\raw"
$gen  = Join-Path $PSScriptRoot "gen.ps1"
$base = Join-Path $raw "santa_base.png"

# Общий стиль — держим одинаковым во всех ассетах, иначе набор рассыплется
$STYLE = "Bold thick uniform black outline, flat cel-shaded coloring, no gradients, no soft shading, high contrast saturated colors, simple bold silhouette that stays readable when scaled down to 48 pixels. Isolated on a solid pure magenta FF00FF background, no shadow, no text, no watermark, no border. Square 1:1 composition, subject fills about 85% of the frame."

# --- варианты носа: правка исходного спрайта, всё кроме носа не трогаем ----
$noses = @(
  @{ n = "santa_c1"; c = "very dark blackberry crimson, almost purple-red, the colour of a nose ruined by decades of drinking" },
  @{ n = "santa_c2"; c = "bright raspberry pink-red" },
  @{ n = "santa_c3"; c = "soft pale pink, only slightly rosier than his cheeks" }
)
foreach ($v in $noses) {
  & $gen -Name $v.n -Ref $base -Prompt "Take the reference Santa Claus sprite and change ONE thing only: the colour of his big round nose becomes $($v.c). Everything else must stay pixel-identical - same pose, same black outline, same red coat, same white beard, same hat, same magenta FF00FF background, same framing, same scale. Do not redraw, do not restyle, do not move anything."
}

# --- остальные ассеты ------------------------------------------------------
$assets = @(
  @{ n = "santa_fly"; ref = $base; p = "Take the reference Santa Claus character and redraw him in a new pose: sober and delighted, standing upright and flying straight up, both arms raised in triumph, legs together and trailing below, hat streaming upward, eyes wide open and happy, wide grin. His nose is now normal peach skin tone, not red. Keep his design identical otherwise - same coat, same beard, same hat, same outline weight, same flat colors. $STYLE" },

  @{ n = "paddle"; ref = ""; p = "A long horizontal wooden juggling stick for a Christmas arcade game, like a polished wooden ski or a candy-striped pole, lying perfectly horizontal. Rounded ends with brass caps. Exactly at its centre is tied a big red satin ribbon bow with two hanging tails - the bow is the visual marker of the sweet spot and must be clearly brighter and more contrasting than the rest of the stick. Seen straight from the side, no perspective, no tilt. $STYLE Wide horizontal object centred in the frame." },

  @{ n = "item_brine"; ref = ""; p = "A glass jar of pickle brine for a Christmas arcade game: a squat round glass jar with a metal screw lid, filled with pale yellow-green cloudy brine, two small pickled cucumbers and a dill sprig visible inside, a few bubbles. Friendly rounded shape, reads as a healing item. $STYLE" },

  @{ n = "item_snack"; ref = ""; p = "A zakuska plate for a Christmas arcade game: a small round plate holding a slice of dark rye bread topped with a herring fillet, a pickled cucumber and a sprig of dill. Friendly rounded shapes, appetizing, reads as a food power-up. $STYLE" },

  @{ n = "item_wide"; ref = ""; p = "A glossy round Christmas tree bauble, deep emerald green with a gold cap and hanging loop, and painted on its front in thick bright white a bold double-headed horizontal arrow pointing left and right. Perfectly round friendly shape, reads as a helpful bonus. $STYLE" },

  @{ n = "item_high"; ref = ""; p = "A glossy round Christmas tree bauble, royal blue with a gold cap and hanging loop, and painted on its front in thick bright white a bold arrow pointing straight up. Perfectly round friendly shape, reads as a helpful bonus. $STYLE" },

  @{ n = "item_slow"; ref = ""; p = "A glossy round Christmas tree bauble, warm violet with a gold cap and hanging loop, and painted on its front in thick bright white a bold arrow pointing straight down. Perfectly round friendly shape, reads as a helpful bonus. $STYLE" },

  @{ n = "item_coal"; ref = ""; p = "A lump of coal for a Christmas arcade game: an aggressively angular jagged black rock with sharp broken facets, cold grey-blue highlights on the edges, a few sharp splinters sticking out, faint orange embers glowing in the cracks. Hostile spiky silhouette, must read as dangerous at a glance and must NOT look round or friendly. $STYLE" },

  @{ n = "item_bottle"; ref = ""; p = "A vodka bottle for a Christmas arcade game: a tall angular dark green glass bottle with sharp shoulders, a long narrow neck, a red foil cap and a blank white label, tilted slightly. Hard angular silhouette, must read as dangerous and must NOT look round or friendly. $STYLE" },

  @{ n = "bg"; ref = ""; p = "Wide 16:9 background for a Christmas arcade game: a snowy Russian village at night seen from a distance, dark navy blue sky, a few small warm-lit windows in low wooden houses along the bottom edge, snow-covered fir trees, a full moon and scattered stars. Deliberately dark, low contrast and desaturated so that bright cartoon characters placed on top stay perfectly readable - this is a backdrop, not a hero image. Bold flat cel-shaded cartoon style with simple shapes and clean outlines, no fine detail, no text, no characters, no foreground objects in the middle of the frame. Landscape 16:9." }
)

foreach ($a in $assets) {
  if ($a.ref) { & $gen -Name $a.n -Ref $a.ref -Prompt $a.p }
  else        { & $gen -Name $a.n -Prompt $a.p }
}

Write-Output "=== готово ==="
Get-ChildItem $raw -Filter *.png | Format-Table Name, Length
