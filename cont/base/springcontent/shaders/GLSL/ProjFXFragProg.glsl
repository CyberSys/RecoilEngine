#version 130

#ifdef USE_TEXTURE_ARRAY
	uniform sampler2DArray atlasTex;
#else
	uniform sampler2D      atlasTex;
#endif

uniform sampler2D depthTex;
uniform float softenThreshold;
uniform vec2 softenExponent;
uniform vec4 alphaCtrl = vec4(0.0, 0.0, 0.0, 1.0); //always pass
uniform vec3 fogColor;
uniform vec2 distUni; // time, uvOffsetMag

in vec4 vCol;
centroid in vec4 vUV;
in float vLayer;
in float vBF;
in float fragDist;
in float fogFactor;
// TODO move into ifdef
in vec3 wsPos;
in vec4 vsPos;
in vec4 vsDistParam2;
in vec2 vsDistParam1;
noperspective in vec2 screenUV;

out vec4 fragColor;
#ifdef WITH_DISTORTION
out vec4 distVec;
#endif

#define projMatrix gl_ProjectionMatrix

#define NORM2SNORM(value) (value * 2.0 - 1.0)
#define SNORM2NORM(value) (value * 0.5 + 0.5)

float GetViewSpaceDepth(float d) {
	#ifndef DEPTH_CLIP01
		d = NORM2SNORM(d);
	#endif
	return -projMatrix[3][2] / (projMatrix[2][2] + d);
}

bool AlphaDiscard(float a) {
	float alphaTestGT = float(a > alphaCtrl.x) * alphaCtrl.y;
	float alphaTestLT = float(a < alphaCtrl.x) * alphaCtrl.z;

	return ((alphaTestGT + alphaTestLT + alphaCtrl.w) == 0.0);
}

// LLM generated derivative of
// https://github.com/BrianSharpe/Wombat/blob/master/Perlin3D.glsl
vec2 Perlin3D2(vec3 P)
{
    // establish our grid cell and unit position
    vec3 Pi = floor(P);
    vec3 Pf = P - Pi;
    vec3 Pf_min1 = Pf - 1.0;

    // clamp the domain
    Pi.xyz = Pi.xyz - floor(Pi.xyz * (1.0 / 69.0)) * 69.0;
    vec3 Pi_inc1 = step(Pi, vec3(69.0 - 1.5)) * (Pi + 1.0);

    // calculate the hash
    vec4 Pt = vec4(Pi.xy, Pi_inc1.xy) + vec2(50.0, 161.0).xyxy;
    Pt *= Pt;
    Pt = Pt.xzxz * Pt.yyww;
    const vec3 SOMELARGEFLOATS = vec3(635.298681, 682.357502, 668.926525);
    const vec3 ZINC = vec3(48.500388, 65.294118, 63.934599);
    vec3 lowz_mod = vec3(1.0 / (SOMELARGEFLOATS + Pi.zzz * ZINC));
    vec3 highz_mod = vec3(1.0 / (SOMELARGEFLOATS + Pi_inc1.zzz * ZINC));
    vec4 hashx0 = fract(Pt * lowz_mod.xxxx);
    vec4 hashx1 = fract(Pt * highz_mod.xxxx);
    vec4 hashy0 = fract(Pt * lowz_mod.yyyy);
    vec4 hashy1 = fract(Pt * highz_mod.yyyy);
    vec4 hashz0 = fract(Pt * lowz_mod.zzzz);
    vec4 hashz1 = fract(Pt * highz_mod.zzzz);

    // calculate the gradients
    vec4 grad_x0 = hashx0 - 0.49999;
    vec4 grad_y0 = hashy0 - 0.49999;
    vec4 grad_z0 = hashz0 - 0.49999;
    vec4 grad_x1 = hashx1 - 0.49999;
    vec4 grad_y1 = hashy1 - 0.49999;
    vec4 grad_z1 = hashz1 - 0.49999;

    // Compute normalization factor (reused for both components)
    vec4 norm0 = inversesqrt(grad_x0 * grad_x0 + grad_y0 * grad_y0 + grad_z0 * grad_z0);
    vec4 norm1 = inversesqrt(grad_x1 * grad_x1 + grad_y1 * grad_y1 + grad_z1 * grad_z1);

    // Cache the distance vectors
    vec4 px = vec2(Pf.x, Pf_min1.x).xyxy;
    vec4 py = vec2(Pf.y, Pf_min1.y).xxyy;
    vec4 pz0 = Pf.zzzz;
    vec4 pz1 = Pf_min1.zzzz;

    // Component 1: Standard Dot Product (grad . dist)
    vec4 dot1_0 = norm0 * (grad_x0 * px + grad_y0 * py + grad_z0 * pz0);
    vec4 dot1_1 = norm1 * (grad_x1 * px + grad_y1 * py + grad_z1 * pz1);

    // Component 2: Orthogonal Dot Product using cyclic permutation (y,z,x)
    // This creates a second uncorrelated noise field with zero extra hashing
    vec4 dot2_0 = norm0 * (grad_y0 * px + grad_z0 * py + grad_x0 * pz0);
    vec4 dot2_1 = norm1 * (grad_y1 * px + grad_z1 * py + grad_x1 * pz1);

    // Classic Perlin Interpolation
    vec3 blend = Pf * Pf * Pf * (Pf * (Pf * 6.0 - 15.0) + 10.0);

    // Interpolate along z-axis for both components
    vec4 res1_0 = mix(dot1_0, dot1_1, blend.z);
    vec4 res2_0 = mix(dot2_0, dot2_1, blend.z);

    // Calculate final weights for xy interpolation
    vec4 blend2 = vec4(blend.xy, vec2(1.0 - blend.xy));
    vec4 weights = blend2.zxzx * blend2.wwyy;

    // Return the two independent noise values
    // Scale to strict -1.0->1.0 range
    float final1 = dot(res1_0, weights) * 1.1547005383792515290182975610039;
    float final2 = dot(res2_0, weights) * 1.1547005383792515290182975610039;

    return vec2(final1, final2);
}

const vec3 LUMA = vec3(0.299, 0.587, 0.114);
const vec2 distCamDist = vec2(10, 3500);

void main() {
	#ifdef USE_TEXTURE_ARRAY
		vec4 c0 = texture(atlasTex, vec3(vUV.xy, vLayer));
		vec4 c1 = texture(atlasTex, vec3(vUV.zw, vLayer));
	#else
		vec4 c0 = texture(atlasTex, vUV.xy);
		vec4 c1 = texture(atlasTex, vUV.zw);
	#endif

	vec4 color = vec4(mix(c0, c1, vBF));
	color *= vCol;

	fragColor = color;
	fragColor.rgb = mix(fragColor.rgb, fogColor * fragColor.a, (1.0 - fogFactor));

	#ifdef SMOOTH_PARTICLES
	float depthZO = texture(depthTex, screenUV).x;
	float depthVS = GetViewSpaceDepth(depthZO);

	if (softenThreshold > 0.0) {
		float edgeSmoothness = smoothstep(0.0, softenThreshold, vsPos.z - depthVS); // soften edges
		fragColor *= pow(edgeSmoothness, softenExponent.x);
	} else {
		float edgeSmoothness = smoothstep(softenThreshold, 0.0, vsPos.z - depthVS); // follow the surface up
		fragColor *= pow(edgeSmoothness, softenExponent.y);
	}
	#endif

	#ifdef WITH_DISTORTION
	//vec2 uvMag = vsDistParam1 * distUni.y;
	vec2 uvMag = vec2(0.05);// * distUni.y;
	vec2 worldPerPixeldX = dFdx(vsPos.xy);
	vec2 worldPerPixeldY = dFdy(vsPos.xy);
	float viewPerPixel = sqrt(dot(worldPerPixeldX, worldPerPixeldX) + dot(worldPerPixeldY, worldPerPixeldY));
	if (dot(uvMag, uvMag) > 0.0) {
		float distTexIntensity = dot(color.rgb, LUMA);
		distTexIntensity = fragColor.a;
		//distVec = vec4(Perlin2D2(10.0 * vsDistParam2.xy * vUV.xy + vsDistParam2.zw * distUni.x) * uvMag * fragColor.a, 0.0, fragColor.a);
		//distVec = vec4(Perlin2D2(vec2(0.08, 0.08) * vsPos.xy  + vec2(1.0, 1.0) * vec2(distUni.x)) * uvMag * pow(distTexIntensity, 0.75), 0.0, distTexIntensity);
		vec3 perlinInput = vec3(0.08, 0.08, 0.08) * wsPos + vec3(1.0, 1.0, 1.0) * vec3(distUni.x);
		distVec = vec4(
			Perlin3D2(perlinInput) * uvMag / viewPerPixel * distTexIntensity, // vec2 uvOffset, premultiplied by distTexIntensity and reciprocal to viewPerPixel
			distTexIntensity * distTexIntensity, // controls LOD level in the combination shader, squared for artistic purpose
			distTexIntensity // controls the blending rate, although not saved in the texture / FBO
		);
		//distVec = vec4(uvMag, distTexIntensity * distTexIntensity, distTexIntensity * distTexIntensity);
		//distVec = vec4(distTexIntensity);
		//distVec.xy *= Perlin3D2(perlinInput) * uvMag;
		//distVec.x *= pow(distTexIntensity, 0.0001);
	} else {
		distVec = vec4(0.0);
	}
	//distVec = vec4(0.0);
	#endif
	//distVec.xy = vec2(0.0);
	//distVec = 10.0 * fragColor.aaaa;
	//#else
	//	distVec = vec4(0.0);
	//#endif
	//fragColor.rgb *= 10.0;

	if (AlphaDiscard(fragColor.a))
		discard;
}