#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 8, local_size_y = 8 ) in;

#include "common.h"

// line segment distance
// https://www.shadertoy.com/view/3tdSDj
float sdSegment ( in vec2 p, in vec2 a, in vec2 b ) {
	float r = 0.0f;
	vec2 ba = b - a;
	vec2 pa = p - a;
	float h = clamp( dot( pa, ba ) / dot( ba, ba ), 0.0f, 1.0f );
	return length( pa - h * ba ) - r;
}

// circular arc distance
// https://www.shadertoy.com/view/3cXSRf
float sdArc ( vec2 p, vec2 c, float aMin, float aMax, float r ) {
	vec2 p1 = r * vec2( cos( aMin ), sin( aMin ) );
	vec2 p2 = r * vec2( cos( aMax ), sin( aMax ) );

	vec2 v1 = p1 - c;
	vec2 v2 = p2 - c;

	// The parameters are over-determined by one degree of freedom.
	// If p1 and p2 are not on the same distance from c, the arc doesn't
	// actually end in p2, but the end cap is still centered there.
	// Uncomment this line if needed to adjust the distance from p2 to c.
	// v2 = normalize(v2)*length(v1);
	vec2 v = p - c;

	// The signs of w.x, w.y are used to determine if we're in the gap
	vec2 w = vec2( dot( v, -vec2( -v1.y, v1.x ) ), dot(v, vec2( -v2.y, v2.x ) ) );
	bool longarc = ( dot( v1, vec2( -v2.y, v2.x ) ) < 0.0f ); // Arc angle > pi

	// Tweak by iq: "fake" OR/AND of booleans by max/min of floats
	float ingap = longarc ? max( w.x, w.y ) : min( w.x, w.y );
	return ( ingap > 0.0f ) ? min( length( p1 - p ), length( p2 - p ) ) : abs( length( v ) - length( v1 ) );
}

void main () {
	// determine location on the image
	uvec2 loc = gl_GlobalInvocationID.xy;

	if ( loc.x < globalData.gridDims.x && loc.x < globalData.gridDims.x ) {

	}

	// iterating through the list of bboxes...
		// if I'm in the bbox, evaluate distance
			// if I'm within some threshold, store this primitive in this grid cell

	// writing a list of integer IDs into the uncompacted grid buffer (+final count, capped at 15)

}
