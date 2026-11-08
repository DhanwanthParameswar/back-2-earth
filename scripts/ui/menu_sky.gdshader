shader_type canvas_item;
// Title-screen space, drawn entirely in code so it fills any window size.
// Works in "menu pixels" (the 640x360 art grid), measured from the screen
// center so the painted logo/buttons always sit on the same part of the sky.
//   - navy space
//   - two pixelated nebula bands (top-left and bottom-right, like the art)
//   - twinkling 1 px stars, 2 px stars and four-point sparkles
// Owner: D. Used by scripts/ui/menu_backdrop.gd.

uniform vec2 rect_size = vec2(640.0, 360.0);   // menu px covered by this rect
uniform float nebula_px = 3.0;                  // nebula pixel block size

const vec3 SPACE = vec3(0.043, 0.047, 0.180);   // #0b0c2e
const vec3 DEEP_BLUE = vec3(0.10, 0.12, 0.38);
const vec3 BLUE = vec3(0.16, 0.22, 0.62);
const vec3 PURPLE = vec3(0.33, 0.20, 0.66);
const vec3 LAVENDER = vec3(0.55, 0.42, 0.88);
const vec3 TEAL = vec3(0.12, 0.42, 0.52);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

// 2x2 ordered dither: lets the nebula step between colors like pixel art.
float bayer(vec2 cell) {
	vec2 m = mod(cell, 2.0);
	return (m.x * 2.0 + m.y * 3.0 - 4.0 * m.x * m.y) / 4.0 + 0.125;
}

// How much nebula is at p (menu px from center), 0..1.
float nebula(vec2 p, float t) {
	// Distance across the band direction (bands run up-and-right).
	float s = p.x * 0.45 + p.y;
	vec2 q = p * 0.012 + vec2(t * 0.004, -t * 0.002);
	float wobble = (fbm(q * 0.6 + 3.0) - 0.5) * 90.0;
	float top = exp(-pow((s + 285.0 + wobble) / 48.0, 2.0));
	float bottom = exp(-pow((s - 205.0 + wobble) / 52.0, 2.0));
	float band = max(top, bottom);
	float clouds = fbm(q * 2.4 + vec2(0.0, t * 0.003));
	return clamp(band * (clouds * 2.5 - 0.6), 0.0, 1.0);
}

vec3 nebula_color(float d, vec2 p, float t) {
	float tint = fbm(p * 0.02 + 40.0 + t * 0.002);
	vec3 c = mix(SPACE, DEEP_BLUE, smoothstep(0.08, 0.25, d));
	c = mix(c, mix(BLUE, TEAL, smoothstep(0.55, 0.75, tint)), smoothstep(0.25, 0.45, d));
	c = mix(c, PURPLE, smoothstep(0.45, 0.65, d) * (1.0 - smoothstep(0.6, 0.8, tint)));
	c = mix(c, LAVENDER, smoothstep(0.72, 0.9, d));
	return c;
}

// Stars on a jittered grid; one possible star per cell.
vec3 stars(vec2 p, float t) {
	vec2 px = floor(p);
	vec3 col = vec3(0.0);
	// Small dots: 1 px.
	{
		float cs = 9.0;
		vec2 cell = floor(px / cs);
		float h = hash(cell + 3.1);
		if (h < 0.22) {
			vec2 at = floor(vec2(hash(cell + 7.7), hash(cell + 1.9)) * cs);
			if (px - cell * cs == at) {
				float tw = 0.55 + 0.45 * sin(t * (1.0 + h * 9.0) + h * 60.0);
				vec3 tint = mix(vec3(1.0), vec3(0.72, 0.62, 1.0), step(0.5, fract(h * 13.0)));
				col += tint * tw * (0.45 + h * 2.0);
			}
		}
	}
	// Bright 2 px stars.
	{
		float cs = 26.0;
		vec2 cell = floor(px / cs);
		float h = hash(cell + 11.3);
		if (h < 0.28) {
			vec2 at = floor(vec2(hash(cell + 2.2), hash(cell + 5.5)) * (cs - 2.0));
			vec2 l = px - cell * cs - at;
			if (l.x >= 0.0 && l.y >= 0.0 && l.x < 2.0 && l.y < 2.0) {
				float tw = 0.5 + 0.5 * sin(t * (0.8 + h * 4.0) + h * 90.0);
				vec3 tint = mix(vec3(0.85, 0.95, 1.0), vec3(0.65, 0.55, 1.0), step(0.6, fract(h * 7.0)));
				col += tint * mix(0.35, 1.0, tw);
			}
		}
	}
	// Four-point sparkles: a bright center with arms that breathe.
	{
		float cs = 70.0;
		vec2 cell = floor(px / cs);
		float h = hash(cell + 21.7);
		if (h < 0.35) {
			vec2 at = floor(vec2(hash(cell + 4.4), hash(cell + 8.8)) * (cs - 12.0)) + 6.0;
			vec2 l = px - cell * cs - at;
			float tw = 0.5 + 0.5 * sin(t * (0.6 + h * 2.0) + h * 70.0);
			float arm = floor(mix(1.0, 3.0 + step(0.2, h) * 2.0, tw));
			float a = 0.0;
			if (l == vec2(0.0)) a = 1.0;
			else if (l.x == 0.0 && abs(l.y) <= arm) a = 1.0 - abs(l.y) / (arm + 1.0);
			else if (l.y == 0.0 && abs(l.x) <= arm) a = 1.0 - abs(l.x) / (arm + 1.0);
			vec3 tint = mix(vec3(1.0, 0.97, 0.9), vec3(0.6, 0.95, 1.0), step(0.17, h));
			col += tint * a * mix(0.5, 1.0, tw);
		}
	}
	return col;
}

void fragment() {
	float t = TIME;
	vec2 p = UV * rect_size - rect_size * 0.5;

	// Nebula, on a coarse pixel grid with dithered color steps.
	vec2 cell = floor(p / nebula_px);
	vec2 np = cell * nebula_px;
	float d = nebula(np, t);
	d = floor(d * 6.0 + bayer(cell)) / 6.0;
	vec3 c = nebula_color(d, np, t);
	// A few bright motes inside the clouds.
	if (d > 0.3 && hash(cell) > 0.985) {
		c = mix(c, LAVENDER * 1.3, 0.6);
	}

	// Stars sit on top, dimmed where the nebula is thick.
	c += stars(p, t) * (1.0 - d * 0.5);
	COLOR = vec4(c, 1.0);
}
