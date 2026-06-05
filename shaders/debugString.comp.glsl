#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

#include "common.h"

// config for the strings...
	// base point -> vec2, rounded down to ivec2 with floor()
	// string length
	// font + color config
	// glyph size -> can come from imageSize()/16
		// because the LUTs are 256 elements arranged in 16x16
	// stored value for string length in characters
	// the string -> this is a sequence of bytes, I can store uint8_t's with

// UBO configuration for writing a string of N characters to the image
layout( set = 0, binding = 1, scalar ) uniform debugStringConfig {
	vec2 debugStringWriteLocation;
	vec4 debugStringFillColor;
	vec4 debugStringBackgroundColor;
	uint debugStringFontPick;
	uint debugStringLength;
	float debugStringDepth;
	uint8_t debugStringData[ 4096 ];
} StringConfig;

// color attachment + depth attachment -> need read/write access
layout ( rgba16f, set = 0, binding = 3 ) uniform image2D colorImage;
layout ( r32f, set = 0, binding = 4 ) uniform image2D depthImage;

// font LUTs -> bind all of them, and switch with an integer
layout ( set = 0, binding = 5 ) uniform sampler2D font_Codepage437;
layout ( set = 0, binding = 6 ) uniform sampler2D font_fatfont;
layout ( set = 0, binding = 7 ) uniform sampler2D font_tinyfont;

// global state -> set in main(), first thing
ivec2 glyphSize;

// glyph mask from the LUT
bool getGlyphMask ( uvec2 pixel, uint pickedGlyph ) {

	// off-glyph returns false
	if ( pixel.x >= glyphSize.x || pixel.y >= glyphSize.y )
		return false;

	// char -> corresponding glyph
	ivec2 baseLocation = glyphSize.xy * ivec2( pickedGlyph % 16, pickedGlyph / 16 );

	vec4 glyphSample;
	switch ( StringConfig.debugStringFontPick ) {
		case 0: glyphSample = texelFetch( font_Codepage437, baseLocation + pixel, 0 ) / 16;
		break;

		case 1: glyphSample = texelFetch( font_fatfont, baseLocation + pixel, 0 ) / 16;
		break;

		case 2: glyphSample = texelFetch( font_tinyfont, baseLocation + pixel, 0 ) / 16;
		break;

		default: break;
	}

	// then you can add the pixel offset and return alpha != 0
	return true;
}

// should this sample write, based on depth?
bool compareDepth () {
	float depthSample = imageLoad( depthImage, gl_GlobalInvocationID.xy );
	return ( depthSample < StringConfig.debugStringDepth );
}

// we have a simple decision
void main () {
	// populate the glyph size in global scope
	switch ( StringConfig.debugStringFontPick ) {
	case 0: glyphSize = textureSize( font_Codepage437, 0 ) / 16;
		break;

	case 1: glyphSize = textureSize( font_fatfont, 0 ) / 16;
		break;

	case 2: glyphSize = textureSize( font_tinyfont, 0 ) / 16;
		break;

	default: break;
	}

	// pixel we are operating on has several chances to early out:
	bool shouldWrite = true;
	bool onGlyph = false;

	// in valid range for string?
	if ( gl_GlobalInvocationID.x > ( ( glyphSize.x + 1 ) * StringConfig.debugStringLength ) || gl_GlobalInvocationID.y > glyphSize.y )
		shouldWrite = false; // out of bounds only needs to do simple greater than check

	// fetch glyph id -> check glyph mask
	uint8_t myGlyph = StringConfig.debugStringData[ gl_GlobalInvocationID.x / ( glyphSize.x + 1 ) ];
	uvec2 pixelOffset = uvec2( gl_GlobalInvocationID.x % ( glyphSize.x + 1 ), gl_GlobalInvocationID.y );
	onGlyph = getGlyphMask( pixelOffset, myGlyph );

	// invisible foreground or background possible, or both if you want
	if ( !onGlyph && ( StringConfig.debugStringBackgroundColor.a == 0.0f ) )
		shouldWrite = false;
	else if ( onGlyph && ( StringConfig.debugStringFillColor.a == 0.0f ) )
		shouldWrite = false;

	// fetch depth -> compare to the UBO depth value for this string
	if ( compareDepth() )
		shouldWrite = false;

	// if we have not rejected yet... write color, depth
	if ( shouldWrite ) {
		// update depth with string depth
		imageStore( depthImage, gl_GlobalInvocationID.xy, vec4( StringConfig.debugStringDepth ) );

		// update color with foreground or background color
		vec3 c = onGlyph ? StringConfig.debugStringFillColor : StringConfig.debugStringBackgroundColor;
		imageStore( colorImage, gl_LocalInvocationID.xy, vec4( c, 1.0f ) );
	}
}