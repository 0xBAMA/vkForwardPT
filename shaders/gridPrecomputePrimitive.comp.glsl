#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 8, local_size_y = 8 ) in;

#include "common.h"

void main () {
	// determine location on the image

	// iterating through the list of bboxes...
		// if I'm in the bbox, evaluate distance
			// if I'm within some threshold, store this primitive in this grid cell

	// writing a list of integer IDs into the uncompacted grid buffer (+final count, capped at 15)

}
