#version 130

in vec2 uv;

uniform sampler2D screenCopyTex;
uniform sampler2D distortionTex;
uniform vec2 params; // numberOfLODs, chromaticOberation

out vec4 fragColor;

void main()
{
	vec3 distTexVal = texture(distortionTex, uv).xyz;
	vec2 uvOff = distTexVal.xy;
	float uvOffMag = length(uvOff);

	float distTexIntensity = distTexVal.z;

	float lodA = distTexIntensity * params.x;
	//lodA = 0.0f;

	fragColor = textureLod(screenCopyTex, uv + uvOff, lodA);
	// Chromatic aberrations
	if (params.y != 0.0 && uvOffMag > 0.0) {
		fragColor.r = textureLod(screenCopyTex, uv + (uvOff * (1.0 + 0.5 * params.y)), lodA).r;
		fragColor.b = textureLod(screenCopyTex, uv + (uvOff * (1.0 - 0.5 * params.y)), lodA).b;
	}
	//fragColor = vec4(100.0 * uvOff, 0.0, 1.0);
	//fragColor = textureLod(screenCopyTex, uv, 0.0);
	//fragColor = vec4(texture(distortionTex, uv).xy);
	//fragColor = vec4(1, 0, 0, 1);
	//fragColor = vec4(vec3(100.0*uvOff, 0.0), 1.0);
	//fragColor = vec4(vec3(lodA), 1.0);
	//fragColor = vec4(100.0 * vec3(uvOffMag), 1.0);

}