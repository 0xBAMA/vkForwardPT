#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_ray_query : require

layout ( local_size_x = 16, local_size_y = 16 ) in;

#include "common.h"
#include "random.h"

layout ( rgba32f, set = 0, binding = 1 ) uniform image2D accumulator;

layout( set = 0, binding = 2 ) uniform accelerationStructureEXT tlas;

void main () {

	// basic camera setup for testing the hardware ray queries...
	mat3 rot = Rotate3D( 0.5f, vec3( 1.0f ) );
	vec3 rayOrigin = rot * vec3(
		remap( gl_GlobalInvocationID.x, 0.0f, imageSize( accumulator ).x, -1.0f, 1.0f ),
		remap( gl_GlobalInvocationID.y, 0.0f, imageSize( accumulator ).y, -1.0f, 1.0f ),
		10.0f );
	vec3 rayDirection = rot * vec3( 0.0f, 0.0f, -1.0f );

	// initializing the query
	rayQueryEXT rayQuery;
	rayQueryInitializeEXT( rayQuery, // Ray query
		tlas,                  // Top-level acceleration structure
		gl_RayFlagsOpaqueEXT,  // Ray flags, here saying "treat all geometry as opaque"
		0xFF,                  // 8-bit instance mask, here saying "trace against all instances"
		rayOrigin,             // Ray origin
		0.0,                   // Minimum t-value
		rayDirection,          // Ray direction
		10000.0f );            // Maximum t-value

	// doing the traversal

}