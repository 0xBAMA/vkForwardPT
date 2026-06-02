#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 8, local_size_y = 8 ) in;

#include "common.h"

// line segment distance
// https://www.shadertoy.com/view/3tdSDj

// circular arc distance
// https://www.shadertoy.com/view/3cXSRf

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
