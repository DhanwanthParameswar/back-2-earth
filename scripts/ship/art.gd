extends RefCounted
## Shared art helpers. Owner: D.
## Missing textures return null so gameplay never depends on art being present.

const TILE := 32

# Palette (PICO-8 based) — keep every placeholder on these colors.
const NAVY := Color("1d2b53")
const STEEL := Color("5f574f")
const STEEL_LIGHT := Color("c2c3c7")
const CYAN := Color("29adff")
const AMBER := Color("ffa300")
const RED := Color("ff004d")
const WHITE := Color("fff1e8")
const BLACK := Color("000000")


static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


## A Sprite2D for `path`, or a flat colored square if the file is missing.
static func make_sprite(path: String, fallback: Color, size := Vector2(TILE, TILE)) -> CanvasItem:
	var t := tex(path)
	if t != null:
		var s := Sprite2D.new()
		s.texture = t
		return s
	var r := ColorRect.new()
	r.color = fallback
	r.size = size
	r.position = -size / 2.0
	return r
