#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 64 ) in;

#include "common.h"
#include "random.h"
#include "hg_sdf.h"

struct raySegment {
	float wavelength;
	float brightness;
	vec2 a;	// first point
	vec2 b;	// second point
};

raySegment getDefaultSegment () {
	raySegment r;
	r.wavelength = 0.0f;
	r.brightness = 0.0f;
	r.a = r.b = vec2( 0.0f );
	return r;
}

layout( set = 0, binding = 1, std430 ) buffer rayBuffer {
	raySegment rays[];
};

layout( set = 0, binding = 2 ) uniform sampler2D iCDFBuffer;
float getWavelengthForLight( uint selectedLight ) {
	return texture( iCDFBuffer, vec2( NormalizedRandomFloat(), ( selectedLight + 0.5f ) / textureSize( iCDFBuffer, 0 ).y ) ).r;
}

layout( set = 0, binding = 3 ) uniform usampler2D pickBuffer;
uint getPickedLight() {
	return texture( pickBuffer, vec2( NormalizedRandomFloat(), NormalizedRandomFloat() ) ).r;
}

struct LightEmitterParameters {
// base emitter
	vec2 position;
	float rotation;

// angular distribution
	float angleScalar;
	float cauchyMix;

// array modifier
	int repeats;
	float emitterSpacing;
	float width;
};

layout( set = 0, binding = 4 ) uniform emitterParameters {
	LightEmitterParameters emitterParams[ 256 ];
} EmitterParameters;

// BVH buffers
layout ( set = 0, binding = 5 ) buffer geometryBuffer {
	float geometryParameters[]; // 16-float stride
};

layout ( set = 0, binding = 6 ) buffer prefixBuffer {
	uint prefixBufferValues[]; // 2-uint stride - elements in order, index, count, index, count...
};

layout ( set = 0, binding = 7 ) buffer gridBuffer {
	uint gridBufferValues[]; // variable stride, requires prefix buffer or it is soup
};

#define NOHIT		0
#define DIFFUSE		1
#define METALLIC	2
#define MIRROR		3
#define DIELECTRIC	4

struct intersectionResult {
// scene intersection representation etc loosely based on Daedalus
	float dist;
	float albedo;
	float IoR;
	float roughness;
	vec2 normal;
	bool frontFacing;
	int materialType;
};

// RT Parameters
const float epsilon = 0.03f;
const float maxDistance = 6000.0f;

intersectionResult getDefaultIntersection () {
	intersectionResult result;
	result.dist = maxDistance;
	result.albedo = 0.0f;
	result.IoR = 0.0f;
	result.roughness = 0.0f;
	result.normal = vec2( 0.0f );
	result.frontFacing = false;
	result.materialType = NOHIT;
	return result;
}

// for the values below that depend on access to the wavelength
float wavelength;

// getting the wavelength-dependent IoR for materials
float evaluateCauchy ( float A, float B, float wms ) {
	return A + B / wms;
}

float evaluateSellmeier ( vec3 B, vec3 C, float wms ) {
	return sqrt( 1.0f + ( wms * B.x / ( wms - C.x ) ) + ( wms * B.y / ( wms - C.y ) ) + ( wms * B.z / ( wms - C.z ) ) );
}

// support for glass behavior
float Reflectance ( const float cosTheta, const float IoR ) {
#if 0
	// Use Schlick's approximation for reflectance
	float r0 = ( 1.0f - IoR ) / ( 1.0f + IoR );
	r0 = r0 * r0;
	return r0 + ( 1.0f - r0 ) * pow( ( 1.0f - cosTheta ), 5.0f );
#elif 0
	// "Full Fresnel", from https://www.shadertoy.com/view/csfSz - this has visible discontinuities
	float g = sqrt( IoR * IoR + cosTheta * cosTheta - 1.0f );
	float a = ( g - cosTheta ) / ( g + cosTheta );
	float b = ( ( g + cosTheta ) * cosTheta - 1.0f ) / ( ( g - cosTheta ) * cosTheta + 1.0f );
	return 0.5f * a * a * ( 1.0f + b * b );
#elif 1
	// https://www.photometric.io/blog/improving-schlicks-approximation/
	float r0 = ( 1.0f - IoR ) / ( 1.0f + IoR );
	r0 = r0 * r0;
	return r0 + ( 1.0f - cosTheta - r0 ) * pow( ( 1.0f - cosTheta ), 4.0f ); // moved cosine term
#endif
	//	another expression used here... https://www.shadertoy.com/view/wlyXzt - what's going on there?
}

float getIORForMaterial ( float packedMaterial ) {
	// There are a couple ways to get IoR from wavelength
	float wavelengthMicrons = wavelength / 1000.0f;
	const float wms = wavelengthMicrons * wavelengthMicrons;

	float IoR = 0.0f;
	vec2 parameters = unpackHalf2x16( floatBitsToUint( packedMaterial ) );
	if ( parameters.x < 0.1f ) {
		// this is one of the default materials
			// that has to be handled separately
	} else {
		// this is a material which needs to evaluate the packed cauchy parameters
		IoR = evaluateCauchy( parameters.x, parameters.y, wms );
	}

	return IoR;
}

int getMaterial ( float packedMaterial ) {
	int mat = 0;
	vec2 parameters = unpackHalf2x16( floatBitsToUint( packedMaterial ) );
	if ( parameters.x < 0.1f ) {
		mat = int( abs( parameters.x ) );
	} else {
		mat = DIELECTRIC;
	}
	return mat;
}

bool gridBoundsCheck ( vec3 p ) {
	return ( all( greaterThanEqual( p, ivec3( 0 ) ) ) && all( lessThanEqual( p, vec3( GlobalData.gridDims, 0 ) ) ) );
}

float cross2( vec2 a, vec2 b ) { return a.x * b.y - a.y * b.x; }

// moving to a symmetric, monotonic no-trig solution using the dot product
float rayArc ( vec2 rO, vec2 rD, vec2 center, float radius, vec2 pTest, float aThresh ) {
	vec2 oc = rO - center;
	float b = dot( oc, rD );
	float c = dot( oc, oc ) - radius * radius;
	float h = b * b - c;

	if ( h < 0.0f ) return -1.0f;
	h = sqrt( h );

	float tClosest = maxDistance;
	for ( int i = 0; i < 2; ++i ) {
		float t = ( i == 0 ) ? ( -b - h ) : ( -b + h );

		vec2 hit = rO + rD * t;
		vec2 dNorm = normalize( hit - center );

		// the test is now  based on:
			// dot( a,b ) == mag( a ) * mag( b ) * cos( theta ) -> vectors normalized, threshold is cos( theta )
		// and then looking to see if the dot product you calculate is greater than the threshold value
		bool inArc = ( dot( dNorm, pTest ) >= aThresh );
		if ( inArc && t > 0.0f && t < tClosest ) {
			tClosest = t;
		}

		// we have a duplicate root for tangent rays
		if ( h == 0.0f ) { // no reason to evaluate twice
			break;
		}
	}
	return tClosest;
}

intersectionResult sceneTraceBVH ( vec2 rayOrigin, vec2 rayDirection ) {
	intersectionResult result = getDefaultIntersection();

	float dClosest = maxDistance;

//#define DDAGRID
#ifdef DDAGRID
	// DDA traversal
	// from https://www.shadertoy.com/view/7sdSzH


	vec3 hitLocation = vec3( rayOrigin / GlobalData.gridScalar, 0.0f );
	vec3 forwards = normalize( vec3( rayDirection, 0.0f ) );
	vec3 deltaDist = 1.0f / abs( forwards );
	ivec3 rayStep = ivec3( sign( forwards ) );
	bvec3 mask0 = bvec3( false );
	ivec3 mapPos0 = ivec3( floor( hitLocation + 0.0f ) );
	vec3 sideDist0 = ( sign( forwards ) * ( vec3( mapPos0 ) - hitLocation ) + ( sign( forwards ) * 0.5f ) + 0.5f ) * deltaDist;

	#define MAX_RAY_STEPS 10000
	for ( int i = 0; i < MAX_RAY_STEPS && gridBoundsCheck( mapPos0 ); i++ ) {
		// Core of https://www.shadertoy.com/view/4dX3zl Branchless Voxel Raycasting
		bvec3 mask1 = lessThanEqual( sideDist0.xyz, min( sideDist0.yzx, sideDist0.zxy ) );
		vec3 sideDist1 = sideDist0 + vec3( mask1 ) * deltaDist;
		ivec3 mapPos1 = mapPos0 + ivec3( vec3( mask1 ) ) * rayStep;

		// consider using distance to hit
		const int linearIndex = 2 * ( mapPos0.x + GlobalData.gridDims.x * mapPos0.y );
		ivec2 prefixValue = ivec2( prefixBufferValues[ linearIndex ], prefixBufferValues[ linearIndex + 1 ] );
		if ( prefixValue.y != 0 ) { // there is a nonzero count for this grid cell

			// iterate over the contents... rare that this will be more than 1, but possible
			float dClosest = maxDistance;
			for ( int i = 0; i < prefixValue.y; i++ ) {
				// we are looking at primitives starting at location 16 * prefixValue.x
				uint primitiveBaseIdx = 16u * ( gridBufferValues[ prefixValue.x + i ] );

#else

			for ( int prim = 0; prim < GlobalData.numPrimitives; prim++ ) {
				// we are looking at primitives starting at location 16 * prefixValue.x
				uint primitiveBaseIdx = 16u * ( prim );

#endif
				// we want to test against the primitive... ( + do not accept if the hit point is outside the grid cell? )
				// math is now operating in pixel space entirely (rayOrigin, rayDirection, and intersection)
				switch ( int( geometryParameters[ primitiveBaseIdx + 15 ] ) ) {
					case 0: // line segment between a and b
					{
						vec2 a = vec2( geometryParameters[ primitiveBaseIdx + 0 ], geometryParameters[ primitiveBaseIdx + 1 ] );
						vec2 b = vec2( geometryParameters[ primitiveBaseIdx + 2 ], geometryParameters[ primitiveBaseIdx + 3 ] );

						// edge
						vec2 edge = b - a;
						float det = cross2( rayDirection, edge );

						// reject, parallel
						bool parallel = false;
						if ( abs( det ) < 1e-9 )
							parallel = true;

						vec2 ao = a - rayOrigin;
						float t = cross2( ao, edge ) / det;
						float u = cross2( ao, rayDirection ) / det;

						// reject based on ray + segment bounds
						bool oobReject = false;
						if ( t < 0.0f || u < 0.0f || u > 1.0f  )
							oobReject = true;

						// cantidate intersection distance is now in t
						 if ( t < dClosest && t > 0.0f && !parallel && !oobReject && !parallel ) {
							// update the hit for the traversal
							result.dist = dClosest = t;

							// determining the normal vector for the surface
							result.normal = normalize( vec2( -edge.y, edge.x ) );
							if ( dot( rayDirection, result.normal ) > 0.0f ) {
//							if ( ( det < 0.0f ) ) {
								// this is a backface hit - we have to invert the normal
								result.normal = -result.normal;

								// IOR is representative of A into B
								result.IoR = getIORForMaterial( geometryParameters[ primitiveBaseIdx + 14 ] )
									/ getIORForMaterial( geometryParameters[ primitiveBaseIdx + 13 ] );

								result.materialType = getMaterial( geometryParameters[ primitiveBaseIdx + 14 ] );
							} else {
								// this is a frontface hit - normal vector is fine
								// IOR is representative of B into A
								result.IoR = getIORForMaterial( geometryParameters[ primitiveBaseIdx + 13 ] )
									/ getIORForMaterial( geometryParameters[ primitiveBaseIdx + 14 ] );

								result.materialType = getMaterial( geometryParameters[ primitiveBaseIdx + 13 ] );
							}

							result.albedo = geometryParameters[ primitiveBaseIdx + 12 ];
							result.roughness = 0.0f;

							// CW edge winding defines front side, or opposite if invert flag is set
//							result.frontFacing = invertFace ? ( det < 0.0f ) : ( det > 0.0f );
						}
					}
					break;

				case 1: // circular arc, centered at p, radius r, and covering a range of theta
					{

						// the basic circle
						vec2 p = vec2( geometryParameters[primitiveBaseIdx + 0 ], geometryParameters[ primitiveBaseIdx + 1 ] );
						float r = geometryParameters[ primitiveBaseIdx + 2 ];

						// theta range
						vec2 centerPt = vec2( geometryParameters[ primitiveBaseIdx + 3 ], geometryParameters[ primitiveBaseIdx + 4 ] );
						float range = geometryParameters[ primitiveBaseIdx + 5 ];

						float t = rayArc( rayOrigin, rayDirection, p, r, centerPt, range );
						if ( t > 0.0f && t < dClosest ) {
							result.dist = dClosest = t;
							vec2 pHit = rayOrigin + rayDirection * t;
							result.normal = normalize( pHit - p );

							// we still need a good shading normal
							if ( dot( rayDirection, result.normal ) > 0.0f ) {
							// this is a backface hit - we have to invert the normal
								result.normal = -result.normal;

								// IOR is representative of A into B
								result.IoR = getIORForMaterial( geometryParameters[ primitiveBaseIdx + 14 ] )
									/ getIORForMaterial( geometryParameters[ primitiveBaseIdx + 13 ] );

								result.materialType = getMaterial( geometryParameters[ primitiveBaseIdx + 14 ] );
							} else {
								// this is a frontface hit - normal vector is fine
								// IOR is representative of B into A
								result.IoR = getIORForMaterial( geometryParameters[ primitiveBaseIdx + 13 ] )
									/ getIORForMaterial( geometryParameters[ primitiveBaseIdx + 14 ] );

								result.materialType = getMaterial( geometryParameters[ primitiveBaseIdx + 13 ] );
							}

							result.albedo = geometryParameters[ primitiveBaseIdx + 12 ];
							result.roughness = 0.0f;
						}
					}
					break;

				// more primitives TBD

				default:
					break;
				}
#ifdef DDAGRID
			}
#endif
			// if we got a good hit in this grid cell, we're going to break
//			if ( result.materialType != NOHIT ) {
//				break;
//			}
		}

#ifdef DDAGRID
		sideDist0 = sideDist1;
		mapPos0 = mapPos1;
	}
#endif

	// can dereference material to get surfaceType, albedo, IoR

	// and give back whatever we got
	return result;
}

void main () {
	// pixel index
	uint loc = uint( gl_GlobalInvocationID.x );
	uint baseIdx = loc * GlobalData.numBounces;

	// seeding RNG, unique per invocation
	seed = PushConstants.wangSeed + 8675309 * loc.x;

	// the raytrace process...
	vec2 rayOrigin, rayDirection;

	// picking a light...
	uint lightPick = getPickedLight();
	LightEmitterParameters params = EmitterParameters.emitterParams[ lightPick ];

	// cache rotation matrix
	const mat2 rot = Rotate2D( params.rotation );
	const vec2 subpixelJitter = vec2( NormalizedRandomFloat(), NormalizedRandomFloat() );

	// values in the buffer set origin, direction
	float pickedRepeat = 0;
	if ( params.repeats != 1 ) {
		pickedRepeat = float( floor( NormalizedRandomFloat() * params.repeats ) ) - float( params.repeats ) / 2.0f;
	}
	vec2 offset = rot * pickedRepeat * params.emitterSpacing * vec2( 1.0f, 0.0f );

	if ( lightPick == 0 ) {
		// this is the mouse light
		rayOrigin = subpixelJitter + GlobalData.mouseLoc.xy + offset + params.width * rot * vec2( NormalizedRandomFloat() - 0.5f, 0.0f );
	} else {
		rayOrigin = subpixelJitter + params.position + offset + params.width * rot * vec2( NormalizedRandomFloat() - 0.5f, 0.0f );
	}
	// direction is the same either way
	rayDirection = normalize( Rotate2D( params.rotation + params.angleScalar * ( NormalizedRandomFloat() - 0.5f ) + params.cauchyMix * rnd_disc_cauchy().x ) * vec2( 0.0f, 1.0f ) );

	// picking a wavelength...
		// importance sampled from the light
	wavelength = getWavelengthForLight( lightPick );

	// initial values... probably redundant
	float transmission = 1.0f;
	float energy = 1.0f;

	bool deadRay = false;
	for ( int i = 0; i < GlobalData.numBounces; i++ ) {
		// we only draw segments until the ray "dies"
		if ( !deadRay ) {

			// do the scene intersection
			intersectionResult result = sceneTraceBVH( rayOrigin, rayDirection );

			// add the line to the system
			raySegment r = getDefaultSegment();
			r.a = rayOrigin;
			r.a.x = remap( r.a.x + NormalizedRandomFloat()- 0.5f, 0.0f, GlobalData.floatBufferResolution.x, -1.0f, 1.0f );
			r.a.y = remap( r.a.y + NormalizedRandomFloat() - 0.5f, 0.0f, GlobalData.floatBufferResolution.y, -1.0f, 1.0f );

			r.b = rayOrigin + result.dist * rayDirection;
			r.b.x = remap( r.b.x + NormalizedRandomFloat(), 0.0f, GlobalData.floatBufferResolution.x, -1.0f, 1.0f );
			r.b.y = remap( r.b.y + NormalizedRandomFloat(), 0.0f, GlobalData.floatBufferResolution.y, -1.0f, 1.0f );

			r.brightness = energy;
			r.wavelength = wavelength;
			rays[ baseIdx + i ] = r;

			// evaluating the russian roulette termination...
			if ( NormalizedRandomFloat() > energy )
				deadRay = true;
			energy *= 1.0f / min( energy, 1.0f ); // compensation term

			if ( energy < 0.001f ) deadRay = true;

			// evaluating the albedo's effect on transmission + energy
			transmission *= result.albedo;
			energy *= result.albedo;

			// epsilon bump + update origin
			rayOrigin = rayOrigin + result.dist * rayDirection + result.normal * epsilon * 3.0f;

			// switch on material type
			switch ( result.materialType ) {
			case DIFFUSE:
				rayDirection = normalize( CircleOffset() );
				// invert if going into the surface
				if ( dot( rayDirection, result.normal ) < 0.0f ) {
					rayDirection = -rayDirection;
				}
				break;

			case METALLIC:
				// todo
				break;

			case MIRROR:
				rayDirection = normalize( reflect( rayDirection, result.normal ) );
				break;

			// below this point, we have to consider the IoR for the specific form of glass or air...
				// because we precomputed all the varying behavior already, we can just treat it uniformly
			case DIELECTRIC:
				rayOrigin -= result.normal * epsilon * 5;
				float cosTheta = min( dot( -normalize( rayDirection ), result.normal ), 1.0f );
				float sinTheta = sqrt( 1.0f - cosTheta * cosTheta );
				bool cannotRefract = ( result.IoR * sinTheta ) > 1.0f; // accounting for TIR effects
				if ( cannotRefract || Reflectance( cosTheta, result.IoR ) > NormalizedRandomFloat() ) {
					rayDirection = normalize( mix( reflect( normalize( rayDirection ), result.normal ), CircleOffset(), result.roughness ).xy );
				} else {
					rayDirection = normalize( mix( refract( normalize( rayDirection ), result.normal, result.IoR ), CircleOffset(), result.roughness ).xy );
				}
				break;

			default:
				break;
			}
		} else {
			// if the ray has finished tracing, we need to zero out the rest of the segment memory, so the raster process doesn't draw anything
			// rays[ baseIdx + i ] = getDefaultSegment(); -> replaced with VkCmdFillBuffer
			break;
		}
	}
}