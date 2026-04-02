#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

#include "common.h"
#include "random.h"

// the accumulator image
layout ( rgba32f, set = 0, binding = 1 ) uniform image2D image;

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