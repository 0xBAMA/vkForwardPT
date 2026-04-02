#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

#include "common.h"
#include "random.h"

// the accumulator image
//layout ( rgba32f, set = 0, binding = 1 ) uniform image2D image;

struct raySegment {
	float wavelength;
	float brightness;
	vec2 a;	// first point
	vec2 b;	// second point
};

layout( set = 0, binding = 1, std430 ) buffer rayBuffer {
	raySegment rays[];
};

void main () {
	// pixel index
	uint loc = uint( gl_GlobalInvocationID.x );
	uint baseIdx = loc * GlobalData.numBounces;

	// seeding RNG
	seed = PushConstants.wangSeed + 8675309 * loc.x;

	// doing the raytrace process...
		// as a placeholder, generating random rays
	// for ( int i = 0; i < GlobalData.numBounces; i++ ) {
	for ( int i = 0; i < 32; i++ ) {
		// rays[ baseIdx + i ].a = vec2( NormalizedRandomFloat(), NormalizedRandomFloat() ) * GlobalData.floatBufferResolution;
		// rays[ baseIdx + i ].b = vec2( NormalizedRandomFloat(), NormalizedRandomFloat() ) * GlobalData.floatBufferResolution;
		rays[ baseIdx + i ].a = vec2( NormalizedRandomFloat(), NormalizedRandomFloat() );
		rays[ baseIdx + i ].b = vec2( NormalizedRandomFloat(), NormalizedRandomFloat() );
	}
}