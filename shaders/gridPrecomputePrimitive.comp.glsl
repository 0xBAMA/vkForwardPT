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

struct geometryStruct {
	float data[ 16 ];
};

layout( set = 0, binding = 1, std430 ) buffer geoBuffer {
	geometryStruct geoData[];
};

layout( set = 0, binding = 2, std430 ) buffer bboxBuffer {
	vec4 bboxes[];
};

layout( set = 0, binding = 3, std430 ) buffer gridCellsUncompacted {
	int gridCells[];
};

void main () {
	// determine location on the image
	uvec2 loc = gl_GlobalInvocationID.xy;

	// place the test point in the middle of the grid cell
	vec2 pTest = loc + vec2( 0.5f ); // location in grid space

	// scaling the point based on the grid scalar
	const float gs = GlobalData.gridScalar;
	pTest *= gs; // convert to pixel space

	// based on half of the diagonal dimension of the grid cell...
		// if the SDF returns less than this, we need to add it to the list for this cell
	const float dThresh = 0.708f * gs;

	// grid bounds check ( we invoke per grid cell, not per pixel )
	int count = 0;
	uint baseIdx = 16 * ( loc.x + GlobalData.gridDims.x * loc.y );

	if ( loc.x < GlobalData.gridDims.x && loc.x < GlobalData.gridDims.x ) {
		// for primitives
		for ( int i = 0; i < GlobalData.numPrimitives && count < 15; i++ ) {
			// if I'm in the bbox, evaluate distance
			vec4 bbox = bboxes[ i ];
			if ( pTest.x <= bbox.x && pTest.x >= bbox.y && pTest.y <= bbox.z && pTest.y >= bbox.w ) {
				bool write = false;
				geometryStruct g = geoData[ i ];

				// handling different primitive types
				switch ( int( g.data[ 15 ] ) ) {
				case 0: { // segment
					const vec2 a = vec2( g.data[ 0 ], g.data[ 1 ] ) / GlobalData.gridScalar;
					const vec2 b = vec2( g.data[ 2 ], g.data[ 3 ] ) / GlobalData.gridScalar;
					const float dSeg = sdSegment( pTest, a, b );
					if ( dSeg < dThresh ) {
						write = true;
					}
					break;
				}

				case 1: { // arc
					vec2 center = vec2( g.data[ 0 ], g.data[ 1 ] ) / GlobalData.gridScalar;
					float r = g.data[ 2 ] / GlobalData.gridScalar;
					float aMin = g.data[ 3 ]; // minimum angle
					float aMax = g.data[ 4 ]; // maximum angle
					const float dArc = sdArc( pTest, center, aMin, aMax, r );
					if ( dArc < dThresh ) {
						write = true;
					}
					break;
				}

				default:
					break;
				}

				if ( write ) {
					// I need to store this index, in the grid cell
					gridCells[ baseIdx + 1 + count ] = i;
					count++;
				}
			}
		}

		// store final count, capped at 15
		gridCells[ baseIdx ] = min( count, 15 );
	}
}
