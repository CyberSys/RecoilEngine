#version 130

in vec2 uv;

uniform sampler2D screenCopyTex;
uniform sampler2D distortionTex;
uniform vec4 params; // time, uvOffMag, numberOfLODs, chromaticOberation

out vec4 fragColor;

// LLM generated derivative of
//  https://github.com/BrianSharpe/Wombat/blob/master/Perlin2D.glsl
vec2 Perlin2D2(in vec2 P)
{
    // Establish our grid cell and unit position
    vec2 Pi = floor(P);
    vec4 Pf_Pfmin1 = P.xyxy - vec4( Pi, Pi + 1.0 );

    // Calculate the hash
    // (This part is identical to the original - high quality, low cost hashing)
    vec4 Pt = vec4( Pi.xy, Pi.xy + 1.0 );
    Pt = Pt - floor(Pt * ( 1.0 / 71.0 )) * 71.0;
    Pt += vec2( 26.0, 161.0 ).xyxy;
    Pt *= Pt;
    Pt = Pt.xzxz * Pt.yyww;
    vec4 hash_x = fract( Pt * ( 1.0 / 951.135664 ) );
    vec4 hash_y = fract( Pt * ( 1.0 / 642.949883 ) );

    // Calculate the gradient vectors
    vec4 grad_x = hash_x - 0.49999;
    vec4 grad_y = hash_y - 0.49999;
    
    // Compute the Normalization factor (reused for both components)
    // We scale things to a strict -1.0->1.0 range here ( *= 1.41421...)
    vec4 norm = inversesqrt( grad_x * grad_x + grad_y * grad_y ) * 1.414213562373095;

    // Cache the distance vectors
    vec4 px = Pf_Pfmin1.xzxz;
    vec4 py = Pf_Pfmin1.yyww;

    // Component 1: Standard Dot Product ( grad . dist )
    vec4 dot1 = norm * ( grad_x * px + grad_y * py );

    // Component 2: Orthogonal Dot Product ( rotate gradient 90 deg: -y, x )
    // This creates a second uncorrelated noise field with zero extra hashing.
    vec4 dot2 = norm * ( -grad_y * px + grad_x * py );

    // Calculate Interpolation Weights (Quintic / Perlin Curve)
    vec2 blend = Pf_Pfmin1.xy * Pf_Pfmin1.xy * Pf_Pfmin1.xy * (Pf_Pfmin1.xy * (Pf_Pfmin1.xy * 6.0 - 15.0) + 10.0);
    vec4 blend2 = vec4( blend, vec2( 1.0 - blend ) );
    
    // Calculate final weights for the 4 corners
    vec4 weights = blend2.zxzx * blend2.wwyy;

    // Return the two independent noise values
    return vec2( dot( dot1, weights ), dot( dot2, weights ) );
}

void main()
{
	float d = 1.0 - texture(distortionTex, uv).x;
	float uvOffsetMag = params.y;
	//uvOffsetMag = 0.005;
	vec2 uvOff = (d == 0.0) ? vec2(0.0) : Perlin2D2(vec2(60.0 * uv.xy + 1.0 * params.x)) * uvOffsetMag * d;
	
    float lodR = clamp(length(uvOff) / uvOffsetMag, 0.0, 1.0);
    float lodA = lodR * params.z;
	
	fragColor = textureLod(screenCopyTex, uv + uvOff, lodA);
	if (params.w != 0.0 && d != 0.0) {
		fragColor.g = textureLod(screenCopyTex, uv + (uvOff * (1.0 + params.w)), lodA).g;
		fragColor.b = textureLod(screenCopyTex, uv + (uvOff * (1.0 - params.w)), lodA).b;
	}
	//fragColor = vec4(200.0 * uvOff, 0.0, 1.0);
}