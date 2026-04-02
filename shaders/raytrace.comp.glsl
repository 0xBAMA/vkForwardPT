#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

#include "common.h"
#include "random.h"

// the accumulator image
layout ( rgba32f, set = 0, binding = 1 ) uniform image2D image;


#define UI0 1597334673U
#define UI1 3812015801U
#define UI2 uvec2(UI0, UI1)
#define UI3 uvec3(UI0, UI1, 2798796415U)
#define UIF (1.0 / float(0xffffffffU))

vec3 hash33( vec3 p ) {
	uvec3 q = uvec3( ivec3( p ) ) * UI3;
	q = ( q.x ^ q.y ^ q.z )*UI3;
	return -1.0 + 2.0 * vec3( q ) * UIF;
}

// Gradient noise by iq (modified to be tileable)
float gradientNoise( vec3 x, float freq ) {
	// grid
	vec3 p = floor( x );
	vec3 w = fract( x );

	// quintic interpolant
	vec3 u = w * w * w * ( w * ( w * 6.0 - 15.0 ) + 10.0 );

	// gradients
	vec3 ga = hash33( mod( p + vec3( 0.0, 0.0, 0.0 ), freq ) );
	vec3 gb = hash33( mod( p + vec3( 1.0, 0.0, 0.0 ), freq ) );
	vec3 gc = hash33( mod( p + vec3( 0.0, 1.0, 0.0 ), freq ) );
	vec3 gd = hash33( mod( p + vec3( 1.0, 1.0, 0.0 ), freq ) );
	vec3 ge = hash33( mod( p + vec3( 0.0, 0.0, 1.0 ), freq ) );
	vec3 gf = hash33( mod( p + vec3( 1.0, 0.0, 1.0 ), freq ) );
	vec3 gg = hash33( mod( p + vec3( 0.0, 1.0, 1.0 ), freq ) );
	vec3 gh = hash33( mod( p + vec3( 1.0, 1.0, 1.0 ), freq ) );

	// projections
	float va = dot( ga, w - vec3( 0.0, 0.0, 0.0 ) );
	float vb = dot( gb, w - vec3( 1.0, 0.0, 0.0 ) );
	float vc = dot( gc, w - vec3( 0.0, 1.0, 0.0 ) );
	float vd = dot( gd, w - vec3( 1.0, 1.0, 0.0 ) );
	float ve = dot( ge, w - vec3( 0.0, 0.0, 1.0 ) );
	float vf = dot( gf, w - vec3( 1.0, 0.0, 1.0 ) );
	float vg = dot( gg, w - vec3( 0.0, 1.0, 1.0 ) );
	float vh = dot( gh, w - vec3( 1.0, 1.0, 1.0 ) );

	// interpolation
	return va +
	u.x * ( vb - va ) +
	u.y * ( vc - va ) +
	u.z * ( ve - va ) +
	u.x * u.y * ( va - vb - vc + vd ) +
	u.y * u.z * ( va - vc - ve + vg ) +
	u.z * u.x * ( va - vb - ve + vf ) +
	u.x * u.y * u.z * ( -va + vb + vc - vd + ve - vf - vg + vh );
}

float perlinfbm( vec3 p, float freq, int octaves ) {
	float G = exp2( -0.85 );
	float amp = 1.0;
	float noise = 0.0;
	for ( int i = 0; i < octaves; ++i ) {
		noise += amp * gradientNoise( p * freq, freq );
		freq *= 2.0;
		amp *= G;
	}
	return noise;
}

vec4 SMPTEtestpattern ( vec2 uv ) {
	// from martymarty https://www.shadertoy.com/view/ctByzK
	float r = uv.x * 7.;
	vec4 z, v = .075 + z,
	c = vec4( 0, .22, .35, .5 );

	if ( uv != clamp( uv, vec2( 0.0f ), vec2( 1.0f ) ) )
		return vec4( 0.0f );

	vec4 O = mod( ceil( r / vec4( 2, 4, 1, 0 ) ) , 2. );

	O = uv.y > .33 ? O * .75
	: uv.y > .25 ? vec4(1.-O.xy, O.zz) * .75*O.z
	: r < 1.25  ? c
	: r < 2.5   ? v/v
	: r < 3.75  ? c.yxwx
	: r < 5.    ? v
	: r < 5.33  ? z
	: r < 6. && r > 5.67 ? z+.15
	: v;

	return vec4( O.xyz, 1.0f );
}

float tMin, tMax; // global state tracking
bool Intersect ( const vec3 rO, vec3 rD ) {
	// Intersect() code adapted from:
	//    Amy Williams, Steve Barrus, R. Keith Morley, and Peter Shirley
	//    "An Efficient and Robust Ray-Box Intersection Algorithm"
	//    Journal of graphics tools, 10(1):49-54, 2005
	const float minDistance = 0.0f;
	const float maxDistance = 10000.0f;
	int s[ 3 ]; // sign toggle
	// inverse of ray direction
	const vec3 iD = vec3( 1.0f ) / rD;
	s[ 0 ] = ( iD[ 0 ] < 0 ) ? 1 : 0;
	s[ 1 ] = ( iD[ 1 ] < 0 ) ? 1 : 0;
	s[ 2 ] = ( iD[ 2 ] < 0 ) ? 1 : 0;
	const vec3 min = vec3( -4.0f, -4.0f, -1.5f );
	const vec3 max = vec3(  4.0f,  4.0f,  1.5f );
	const vec3 b[ 2 ] = { min, max }; // bounds
	tMin = ( b[ s[ 0 ] ][ 0 ] - rO[ 0 ] ) * iD[ 0 ];
	tMax = ( b[ 1 - s[ 0 ] ][ 0 ] - rO[ 0 ] ) * iD[ 0 ];
	const float tYMin = ( b[ s[ 1 ] ][ 1 ] - rO[ 1 ] ) * iD[ 1 ];
	const float tYMax = ( b[ 1 - s[ 1 ] ][ 1 ] - rO[ 1 ] ) * iD[ 1 ];
	if ( ( tMin > tYMax ) || ( tYMin > tMax ) ) return false;
	if ( tYMin > tMin ) tMin = tYMin;
	if ( tYMax < tMax ) tMax = tYMax;
	const float tZMin = ( b[ s[ 2 ] ][ 2 ] - rO[ 2 ] ) * iD[ 2 ];
	const float tZMax = ( b[ 1 - s[ 2 ] ][ 2 ] - rO[ 2 ] ) * iD[ 2 ];
	if ( ( tMin > tZMax ) || ( tZMin > tMax ) ) return false;
	if ( tZMin > tMin ) tMin = tZMin;
	if ( tZMax < tMax ) tMax = tZMax;
	return ( ( tMin < maxDistance ) && ( tMax > minDistance ) );
}

float vmax(vec3 v) {
	return max(max(v.x, v.y), v.z);
}
// Box: correct distance to corners
float fBox(vec3 p, vec3 b) {
	vec3 d = abs(p) - b;
	return length(max(d, vec3(0))) + vmax(min(d, vec3(0)));
}

float de ( vec3 p ) {
	p.z += 0.5f;
#define fold45(p)(p.y>p.x)?p.yx:p
	float scale = 2.1, off0 = .8, off1 = .3, off2 = .83;
	vec3 off =vec3(2.,.2,.1);
	float s=1.0;
	for(int i = 0;++i<20;) {
		p.xy = abs(p.xy);
		p.xy = fold45(p.xy);
		p.y -= off0;
		p.y = -abs(p.y);
		p.y += off0;
		p.x += off1;
		p.xz = fold45(p.xz);
		p.x -= off2;
		p.xz = fold45(p.xz);
		p.x += off1;
		p -= off;
		p *= scale;
		p += off;
		s *= scale;
	}
	return length(p)/s;
}

//=============================================================================================================================
const float epsilon = 0.001f;
//=============================================================================================================================
vec3 SDFNormal( in vec3 position ) {
	vec2 e = vec2( epsilon, 0.0f );
	return normalize( vec3( de( position ) ) - vec3( de( position - e.xyy ), de( position - e.yxy ), de( position - e.yyx ) ) );
}
//=============================================================================================================================
vec3 normal;
float raymarch ( vec3 rO, vec3 rD, float tMinV, float tMaxV ) {
	float dQuery = 0.0f;
	float dTotal = tMinV;
	vec3 pQuery;
	for ( int steps = 0; steps < 300; steps++ ) {
		pQuery = rO + dTotal * rD;
		dQuery = de( pQuery );
		dTotal += dQuery * 0.9f; // small understep
		if ( dTotal > tMaxV || abs( dQuery ) < epsilon ) {
			break;
		}
	}
	if ( dTotal < tMinV ) { dTotal = tMinV; }
	if ( dTotal > tMaxV ) { dTotal = tMaxV; }
	normal = SDFNormal( rO + dTotal * rD );
	return dTotal;
}

float raymarch ( vec3 rO, vec3 rD ) {
	return raymarch( rO, rD, tMin, tMax );
}

vec3 getColorSample ( ivec2 pixelIndex ) {
	vec3 color = vec3( 0.0f );
	vec2 uv = 4.0f * ( ( ( pixelIndex + vec2( NormalizedRandomFloat(), NormalizedRandomFloat() ) ) / vec2( imageSize( image ).xy ) ) - vec2( 0.5f ) );
	uv.x *= float( imageSize( image ).x ) / float( imageSize( image ).y );

	/*
	vec2 uv =  pixelIndex / vec2( imageSize( image ).xy );
	uv.y = 1.0f - uv.y;

	color = SMPTEtestpattern( uv ).xyz;
	*/

	const vec3 rO = ( GlobalData.rotation * vec4( uv, -10.0f, 1.0f ) ).xyz;
	const vec3 rD = normalize( ( GlobalData.rotation * vec4( 0.0f, 0.0f, 1.0f, 0.0f ) ).xyz );

	if ( Intersect( rO, rD ) ) {
		// color = SMPTEtestpattern( uv ).xyz * ( 1.0f / tMin );
		// color = vec3( 1.0f / tMin );
		float d = raymarch( rO, rD );
//		color = vec3( 1.0f / d );

		// if we got a positive distance...
		if ( d != tMin ) {
			// is the hit point in shadow
			vec3 pShadow = rO + d * rD;
			vec3 pLight = vec3( 0.0f, 0.0f, -0.3f );
			vec3 dLight = normalize( pLight - pShadow );
			if ( raymarch( pShadow, dLight, 2.0f * epsilon, 100.0f ) >= distance( pShadow, pLight ) ) {
				color += 0.1f + 0.1f * dot( normal, dLight ) * vec3( 0.3f, 0.5f, 0.3f );
			}

			// delta tracking from tMin to the hit point
			vec3 p0 = rO + tMin * rD;
			float tTotal = 0.0f;
			for ( int i = 0; i < 1000; i++ ) {
				float t = -log( NormalizedRandomFloat() );
				tTotal += t;
				p0 += t * rD;
				if ( tTotal > d ) {
					break; // no atmospheric involvement
				} else {
					const float density = exp( -0.1f );
					if ( density < NormalizedRandomFloat() ) {
						// occlusion check to the center point light
						dLight = -normalize( pLight - p0 );
						if ( raymarch( p0, dLight, 2.0f * epsilon, 100.0f ) >= distance( p0, pLight ) ) {
							color += vec3( 1.0f, 0.4f, 0.1f );
						} else {
//							color += vec3( 0.1f );
						}
					}
				}
			}
		}
	}

	return color;
}

void main () {
	// pixel index
	ivec2 loc = ivec2( gl_GlobalInvocationID.xy );

	// seeding RNG
	seed = PushConstants.wangSeed + 69420 * loc.x + 8675309 * loc.y;

	// generate a color value
	vec3 color = getColorSample( loc );

	vec4 data = vec4( color, 1.0f );
	if ( GlobalData.reset == 0 ) {
		// Average with the prior value
		vec4 prevColor = imageLoad( image, loc );
		float sampleCount = prevColor.a + 1.0f;
		const float mixFactor = 1.0f / sampleCount;
		data = vec4( ( any( isnan( color.rgb ) ) ) ? vec3( 0.0f ) : mix( prevColor.rgb, color.rgb, mixFactor ), sampleCount );
	}

	// store back to the running image
	imageStore( image, loc, vec4( data ) );
}