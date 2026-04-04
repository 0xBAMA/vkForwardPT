#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

layout ( local_size_x = 64 ) in;

#include "common.h"
#include "random.h"
#include "hg_sdf.glsl"

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

#define NOHIT						0
#define DIFFUSE						1
#define METALLIC					2
#define MIRROR						3

// air reserve value
#define AIR							5
// below this point, we have specific forms of glass
#define CAUCHY_FUSEDSILICA			6
#define CAUCHY_BOROSILICATE_BK7		7
#define CAUCHY_HARDCROWN_K5			8
#define CAUCHY_BARIUMCROWN_BaK4		9
#define CAUCHY_BARIUMFLINT_BaF10	10
#define CAUCHY_DENSEFLINT_SF10		11
// more coefficients available at https://web.archive.org/web/20151011033820/http://www.lacroixoptical.com/sites/default/files/content/LaCroix%20Dynamic%20Material%20Selection%20Data%20Tool%20vJanuary%202015.xlsm
#define SELLMEIER_BOROSILICATE_BK7	12
#define SELLMEIER_SAPPHIRE			13
#define SELLMEIER_FUSEDSILICA		14
#define SELLMEIER_MAGNESIUMFLOURIDE	15

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

intersectionResult getDefaultIntersection () {
	intersectionResult result;
	result.dist = 0.0f;
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

// global state tracking
int hitSurfaceType = 0;
float hitRoughness = 0.0f;
float hitAlbedo = 0.0f;

// raymarch parameters
const float epsilon = 0.1f;
const float maxDistance = 6000.0f;
const int maxSteps = 200;

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
	#else
	// "Full Fresnel", from https://www.shadertoy.com/view/csfSz7
	float g = sqrt( IoR * IoR + cosTheta * cosTheta - 1.0f );
	float a = ( g - cosTheta ) / ( g + cosTheta );
	float b = ( ( g + cosTheta ) * cosTheta - 1.0f ) / ( ( g - cosTheta ) * cosTheta + 1.0f );
	return 0.5f * a * a * ( 1.0f + b * b );
	#endif
	//	another expression used here... https://www.shadertoy.com/view/wlyXzt - what's going on there?
}

float getIORForMaterial ( int material ) {
	// There are a couple ways to get IoR from wavelength
	float wavelengthMicrons = wavelength / 1000.0f;
	const float wms = wavelengthMicrons * wavelengthMicrons;

	float IoR = 0.0f;
	switch ( material ) {
		// Cauchy second order approx
		case CAUCHY_FUSEDSILICA:			IoR = evaluateCauchy( 1.4580f, 0.00354f, wms ); break;
		case CAUCHY_BOROSILICATE_BK7:		IoR = evaluateCauchy( 1.5046f, 0.00420f, wms ); break;
		case CAUCHY_HARDCROWN_K5:			IoR = evaluateCauchy( 1.5220f, 0.00459f, wms ); break;
		case CAUCHY_BARIUMCROWN_BaK4:		IoR = evaluateCauchy( 1.5690f, 0.00531f, wms ); break;
		case CAUCHY_BARIUMFLINT_BaF10:		IoR = evaluateCauchy( 1.6700f, 0.00743f, wms ); break;
		case CAUCHY_DENSEFLINT_SF10:		IoR = evaluateCauchy( 1.7280f, 0.01342f, wms ); break;
		// Sellmeier third order approx
		case SELLMEIER_BOROSILICATE_BK7:	IoR = evaluateSellmeier( vec3( 1.03961212f, 0.231792344f, 1.01046945f ), vec3( 1.01046945f, 6.00069867e-3f, 2.00179144e-2f ), wms ); break;
		case SELLMEIER_SAPPHIRE:			IoR = evaluateSellmeier( vec3( 1.43134930f, 0.650547130f, 5.34140210f ), vec3( 5.34140210f, 5.27992610e-3f, 1.42382647e-2f ), wms ); break;
		case SELLMEIER_FUSEDSILICA:			IoR = evaluateSellmeier( vec3( 0.69616630f, 0.407942600f, 0.89747940f ), vec3( 0.89747940f, 0.00467914800f, 0.01351206000f ), wms ); break;
		case SELLMEIER_MAGNESIUMFLOURIDE:	IoR = evaluateSellmeier( vec3( 0.48755108f, 0.398750310f, 2.31203530f ), vec3( 2.31203530f, 0.00188217800f, 0.00895188800f ), wms ); break;
		default: IoR = 1.0f;
	}

	return IoR;
}

bool isRefractive ( int id ) {
	return id >= CAUCHY_FUSEDSILICA;
}

mat2 Rotate2D ( in float a ) {
	float c = cos( a ), s = sin( a );
	return mat2( c, s, -s, c );
}

// Hash by David_Hoskins
#define UI0 1597334673U
#define UI1 3812015801U
#define UI2 uvec2(UI0, UI1)
#define UI3 uvec3(UI0, UI1, 2798796415U)
#define UIF (1.0 / float(0xffffffffU))

vec3 hash33( vec3 p ) {
	uvec3 q = uvec3( ivec3( p ) ) * UI3;
	q = ( q.x ^ q.y ^ q.z )*UI3;
	return -1.0 + 2.0 * vec3( q ) * UIF;
}

// should we invert the refractive stuff -> needs to be handled differently for lens elements?
bool invert = false;

float rectangle ( vec2 samplePosition, vec2 halfSize ) {
	vec2 componentWiseEdgeDistance = abs( samplePosition ) - halfSize;
	float outsideDistance = length( max( componentWiseEdgeDistance, 0 ) );
	float insideDistance = min( max( componentWiseEdgeDistance.x, componentWiseEdgeDistance.y ), 0 );
	return outsideDistance + insideDistance;
}

// for the walls
float rayPlaneIntersect ( in vec3 rayOrigin, in vec3 rayDirection ) {
	const vec3 normal = vec3( 0.0f, 1.0f, 0.0f );
	const vec3 planePt = vec3( 0.0f, 0.0f, 0.0f );
	return -( dot( rayOrigin - planePt, normal ) ) / dot( rayDirection, normal );
}

float de ( vec2 p ) {
	float sceneDist = 100000.0f;
	const vec2 pOriginal = p;

	hitAlbedo = 0.0f;
	hitSurfaceType = NOHIT;
	hitRoughness = 0.0f;

	if ( true ) {
		p = Rotate2D( 0.3f ) * pOriginal;
		vec2 gridIndex;
		gridIndex.x = pModInterval1( p.x, 10.0f, -100.0f, 100.0f );
		gridIndex.y = pModInterval1( p.y, 10.0f, -60.0f, 120.0f );
		{ // an example object (refractive)
			uint seedCache = seed;
			seed = 31415 * uint( gridIndex.x ) + uint( gridIndex.y ) * 42069 + 999999;
			const vec3 noise = 0.5f * hash33( vec3( gridIndex.xy, 0.0f ) ) + vec3( 2.0f );
			const float d = ( invert ? -1.0f : 1.0f ) * ( ( noise.z > 0.25f ) ? ( distance( p, vec2( 0.0f ) ) - 2.0f * noise.z ) : ( ( distance( p, vec2( 0.0f ) ) - ( 2.40f * noise.y ) ) ) );
			seed = seedCache;
			sceneDist = min( sceneDist, d );
			if ( sceneDist == d && d < epsilon ) {
				hitSurfaceType = SELLMEIER_BOROSILICATE_BK7;
				hitAlbedo = 1.0f;
			}
		}
	}

	// walls at the edges of the screen for the rays to bounce off of
	if ( true ) {
		const float d = min( min( min(
		rectangle( pOriginal - vec2( 0.0f, 0.0f ), vec2( 4000.0f, 20.0f ) ),
		rectangle( pOriginal - vec2( 0.0f, GlobalData.floatBufferResolution.x ), vec2( 4000.0f, 20.0f ) ) ),
		rectangle( pOriginal - vec2( 0.0f, 0.0f ), vec2( 20.0f, 3000.0f ) ) ),
		rectangle( pOriginal - vec2( GlobalData.floatBufferResolution.y, 0.0f ), vec2( 20.0f, 3000.0f ) ) );
		sceneDist = min( sceneDist, d );
		if ( sceneDist == d && d < epsilon ) {
			hitSurfaceType = MIRROR;
			hitAlbedo = 0.3f;
		}
	}

	// get back final result
	return sceneDist;
}

// function to get the normal
vec2 SDFNormal ( vec2 p ) {
	const vec2 k = vec2( 1.0f, -1.0f );
	return normalize(
		k.xx * de( p + k.xx * epsilon ).x +
		k.xy * de( p + k.xy * epsilon ).x +
		k.yx * de( p + k.yx * epsilon ).x +
		k.yy * de( p + k.yy * epsilon ).x );
}

// trace against the scene
intersectionResult sceneTrace ( vec2 rayOrigin, vec2 rayDirection ) {
	intersectionResult result = getDefaultIntersection();

	// is the initial sample point inside? -> toggle invert so we correctly handle refractive objects
	if ( de( rayOrigin ) < 0.0f ) { // this is probably a solution for the same problem in Daedalus, too...
		invert = !invert;
	}

	// if, after managing potential inversion, we still get a negative result back... we are inside solid scene geometry
	if ( de( rayOrigin ) < 0.0f ) {
		result.dist = -1.0f;
		result.materialType = NOHIT;
		result.albedo = hitAlbedo;
	} else {
		// we're in a valid location and clear to do a raymarch
		result.dist = 0.0f;
		for ( int i = 0; i < maxSteps; i++ ) {
			float d = de( rayOrigin + result.dist * rayDirection );
			if ( d < epsilon ) {
				// we have a hit - gather intersection information
				result.materialType = hitSurfaceType;
				result.albedo = hitAlbedo;
				result.frontFacing = !invert; // for now, this will be sufficient to make decisions re: IoR
				result.IoR = getIORForMaterial( hitSurfaceType );
				result.normal = SDFNormal( rayOrigin + result.dist * rayDirection );
				result.roughness = hitRoughness;
			} else if ( result.dist > maxDistance ) {
				result.materialType = NOHIT;
				break;
			}
			result.dist += d;
		}
	}

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
		// sets origin, direction

	// picking a wavelength...
		// importance sampled from the light

	// placeholder mouse light, uniform point with uniform distribution
	rayOrigin = GlobalData.mouseLoc;
	rayDirection = normalize( CircleOffset().xy );
	wavelength = remap( pow( NormalizedRandomFloat(), 0.6f ), 0.0f, 1.0f, 380.0f, 830.0f );

	// initial values... probably redundant
	float transmission = 1.0f;
	float energy = 1.0f;

	bool deadRay = false;
	for ( int i = 0; i < GlobalData.numBounces; i++ ) {
		// we only draw segments until the ray "dies"
		if ( !deadRay ) {

			// do the scene intersection
			intersectionResult result = sceneTrace( rayOrigin, rayDirection );

			// add the line to the system
			raySegment r = getDefaultSegment();
			r.a = rayOrigin;
			r.a.x = remap( r.a.x, 0.0f, GlobalData.floatBufferResolution.x, -1.0f, 1.0f );
			r.a.y = remap( r.a.y, 0.0f, GlobalData.floatBufferResolution.y, -1.0f, 1.0f );

			r.b = rayOrigin + result.dist * rayDirection;
			r.b.x = remap( r.b.x, 0.0f, GlobalData.floatBufferResolution.x, -1.0f, 1.0f );
			r.b.y = remap( r.b.y, 0.0f, GlobalData.floatBufferResolution.y, -1.0f, 1.0f );

			r.brightness = energy;
			r.wavelength = wavelength;
			rays[ baseIdx + i ] = r;

			// evaluating the russian roulette termination
			if ( NormalizedRandomFloat() > energy )
				deadRay = true;
			energy *= 1.0f / energy; // compensation term

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
				rayDirection = reflect( rayDirection, result.normal );
				break;

				// below this point, we have to consider the IoR for the specific form of glass... because we precomputed all the
				// varying behavior already, we can just treat it uniformly, only need to consider frontface/backface for inversion
			default:
				rayOrigin -= result.normal * epsilon * 5;
				result.IoR = result.frontFacing ? ( 1.0f / result.IoR ) : ( result.IoR ); // "reverse" back to physical properties for IoR
				float cosTheta = min( dot( -normalize( rayDirection ), result.normal ), 1.0f );
				float sinTheta = sqrt( 1.0f - cosTheta * cosTheta );
				bool cannotRefract = ( result.IoR * sinTheta ) > 1.0f; // accounting for TIR effects
				if ( cannotRefract || Reflectance( cosTheta, result.IoR ) > NormalizedRandomFloat() ) {
					rayDirection = normalize( mix( reflect( normalize( rayDirection ), result.normal ), CircleOffset(), result.roughness ).xy );
				} else {
					rayDirection = normalize( mix( refract( normalize( rayDirection ), result.normal, result.IoR ), CircleOffset(), result.roughness ).xy );
				}
				break;
			}
		} else {
			// if the ray has finished tracing, we need to zero out the rest of the segment memory, so the raster process doesn't draw anything
			rays[ baseIdx + i ] = getDefaultSegment();
		}
	}
}