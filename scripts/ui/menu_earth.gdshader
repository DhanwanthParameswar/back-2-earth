shader_type canvas_item;
// Pixel-art Earth for the title: a real sphere on a coarse pixel grid,
// slowly spinning. Land comes from earth_map.png (tools/make_logo.py), clouds
// from noise on the sphere, lit from the upper left with stepped shading.
// Outside -> in: dark outline, cyan atmosphere ring, planet. Owner: D.

uniform sampler2D world_map : filter_nearest, repeat_enable;
uniform float grid = 50.0;            // art pixels across this rect
uniform float planet_radius = 23.0;   // art px
uniform float spin_seconds = 48.0;    // one full turn

const vec3 OUTLINE = vec3(0.07, 0.04, 0.20);
const vec3 ATMOS = vec3(0.24, 0.94, 1.0);
const vec3 ATMOS_DIM = vec3(0.10, 0.55, 0.80);
const vec3 CLOUD = vec3(0.96, 0.97, 1.0);

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float bayer(vec2 cell) {
	vec2 m = mod(cell, 2.0);
	return (m.x * 2.0 + m.y * 3.0 - 4.0 * m.x * m.y) / 4.0 + 0.125;
}

void fragment() {
	vec2 cell = floor(UV * grid);
	vec2 c = cell + 0.5 - vec2(grid * 0.5);   // art px from center
	float d = length(c);
	if (d > planet_radius + 2.0) {
		COLOR = vec4(0.0);
	} else if (d > planet_radius + 1.0) {
		COLOR = vec4(OUTLINE, 1.0);
	} else if (d > planet_radius) {
		// Atmosphere ring: bright on the lit (upper-left) side.
		float lit = dot(normalize(c), normalize(vec2(-1.0, -1.0)));
		COLOR = vec4(lit > -0.3 ? ATMOS : ATMOS_DIM, 1.0);
	} else {
		vec3 n = vec3(c / planet_radius, 0.0);
		n.z = sqrt(max(0.0, 1.0 - dot(n.xy, n.xy)));
		// Tilt the axis ~20 degrees, then spin.
		float tilt = 0.35;
		vec3 t = vec3(n.x * cos(tilt) - n.y * sin(tilt), n.x * sin(tilt) + n.y * cos(tilt), n.z);
		float lat = asin(clamp(-t.y, -1.0, 1.0));
		float lon = atan(t.x, t.z) + TIME * 6.2831853 / spin_seconds;
		vec2 map_uv = vec2(lon / 6.2831853 + 0.5, 0.5 - lat / 3.1415927);
		vec3 col = texture(world_map, map_uv).rgb;

		// Clouds drift a little faster than the ground.
		float clon = lon + TIME * 0.02;
		vec3 sp = vec3(cos(lat) * cos(clon), sin(lat), cos(lat) * sin(clon));
		float cl = noise3(sp * 3.2 + 4.0) * 0.65 + noise3(sp * 7.0) * 0.35;
		if (cl > 0.6) col = CLOUD;

		// Stepped light from the upper left, dithered at the edges between steps.
		float l = dot(n, normalize(vec3(-0.5, -0.55, 0.67))) + (bayer(cell) - 0.5) * 0.18;
		if (l > 0.72) col = mix(col, vec3(1.0), 0.22);
		else if (l > 0.12) col = col;
		else if (l > -0.25) col *= 0.62;
		else col *= 0.36;
		// Thin bright rim just inside the edge (atmosphere glow).
		if (d > planet_radius - 1.0 && l > 0.0) col = mix(col, ATMOS, 0.45);
		COLOR = vec4(col, 1.0);
	}
}
