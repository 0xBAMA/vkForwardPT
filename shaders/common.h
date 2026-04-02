//=========================================================
// push constants block - updated at smallest scope
layout( push_constant ) uniform constants {
// RNG seeding from the CPU
	uint wangSeed;
} PushConstants;

//=========================================================
// Global config etc data in a UBO
layout( set = 0, binding = 0 ) uniform globalData {
	// buffer resolutions:
	uvec2 floatBufferResolution;
	uvec2 presentBufferResolution;

	mat4 rotation;
	mat4 inverseRotation;

	int frameNumber;
	int reset;
	float aspectRatio;
	float invAspectRatio;
	int numPoints;
	int numForces;
} GlobalData;
//=========================================================

#ifndef saturate
#define saturate(x) clamp(x, 0, 1)
#endif

#ifndef UINT_MAX
#define UINT_MAX (0xFFFFFFFF-1)
#endif

#ifndef PI_DEFINED
#define PI_DEFINED
const float pi = 3.141592f;
const float tau = 2.0f * pi;
const float sqrtpi = 1.7724538509f;
#endif