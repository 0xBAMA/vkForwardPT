#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

#include "common.h"

// color attachment, to draw to (this is just going to overwrite)

// font LUTs -> bind all of them, and switch with an integer

// config for the strings...
	// base point -> vec2, rounded down to ivec2 with floor()
	// the string -> this is a sequence of bytes, I can store uint8_t's with
	// string length
	// glyph size -> can come from imageSize()/16
		// because the LUTs are 256 elements arranged in 16x16