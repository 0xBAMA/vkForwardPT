#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 64 ) in;

#include "common.h"

void main () {
	// bounds checking based on current primitive count
	const uint idx = gl_GlobalInvocationID.x;
	if ( idx < GlobalData.numPrimitives ) {
		// load the data for this primitive

		// compute the bbox

		// store the bbox parameters to the buffer

	}
}
