shader_type canvas_item;

// ウェブカメラ映像風の加工（粗い解像度・ノイズ・色ずれ・暗部の持ち上げ・ちらつき）
uniform float time = 0.0;
uniform vec2 res = vec2(240.0, 135.0);
uniform float noise_amt = 0.10;
uniform float glitch = 0.0;   // 0〜1。映像の乱れ（人影が濃いほど強くする）。0なら何も起きない
uniform float dim = 0.0;      // 0〜1。きしみに合わせて一瞬だけ暗転させる（点滅表現）

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = floor(UV * res) / res;
	// 映像の乱れ: 一部の横帯が、短い間だけ左右にずれる
	if (glitch > 0.0) {
		float slice = floor(UV.y * 22.0);
		float tick = floor(time * 7.0);
		if (hash(vec2(slice, tick)) > 1.0 - 0.22 * glitch) {
			uv.x = clamp(uv.x + (hash(vec2(tick, slice + 3.0)) - 0.5) * 0.07 * glitch, 0.0, 1.0);
		}
	}
	// 色ずれ（赤と青を左右にずらす）
	float sh = 0.0025;
	float r = texture(TEXTURE, uv + vec2(sh, 0.0)).r;
	float g = texture(TEXTURE, uv).g;
	float b = texture(TEXTURE, uv - vec2(sh, 0.0)).b;
	vec3 c = vec3(r, g, b);
	// 暗部を持ち上げて、緑がかった安いカメラの色にする（プラン 13: 控えめに）
	c = pow(c, vec3(0.92));
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 0.8) * vec3(0.96, 1.02, 0.97);
	// ノイズ
	float n = hash(uv * res + fract(time) * 37.0) - 0.5;
	c += n * noise_amt;
	// 走査線（プラン 13: 0.94→0.97 で薄く）
	c *= 0.97 + 0.03 * sin(UV.y * res.y * 3.14159);
	// 全体のちらつき（プラン 13: 0.03→0.015 で控えめに）
	c *= 1.0 + 0.015 * sin(time * 47.0) + 0.01 * sin(time * 13.0);
	// 四隅を暗く（プラン 13: 1.1→0.7 で vignette 軽減）
	vec2 q = UV - 0.5;
	c *= 1.0 - dot(q, q) * 0.7;
	// きしみに合わせた暗転（点滅）
	c *= 1.0 - dim * 0.6;
	COLOR = vec4(c, 1.0);
}
