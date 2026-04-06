#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

#include "common.h"

// raster color attachment and the accumulator
layout ( set = 0, binding = 1 ) uniform sampler2D rasterImage;
layout ( rgba32f, set = 0, binding = 2 ) uniform image2D accumulator;

void main () {
	// get the sum
	const ivec2 loc = ivec2( gl_GlobalInvocationID.xy );
	vec4 sum =
		texture( rasterImage, ( vec2( loc ) + vec2( 0.5f ) ) / textureSize( rasterImage, 0 ) ) +
		imageLoad( accumulator, loc );

	if ( GlobalData.reset != 0 )
		sum = vec4( 0.0f );

	// store the result
	 imageStore( accumulator, loc, sum );
}