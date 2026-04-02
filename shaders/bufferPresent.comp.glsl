#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

#include "common.h"

// the draw image
layout ( rgba16f, set = 0, binding = 1 ) uniform image2D image;

// the state image
layout ( set = 0, binding = 2 ) uniform sampler2D state;

void main () {
	// Computing a UV for the texture sampling operation
	vec2 loc = ( gl_GlobalInvocationID.xy + vec2( 0.5f ) ) / imageSize( image ).xy;

	// Sample the image and store the result
	imageStore( image, ivec2( gl_GlobalInvocationID.xy ), ( distance() < 100.0f ) ? vec4( 1.0f, 0.0f, 0.0f, 1.0f ) : texture( state, loc ) );
}