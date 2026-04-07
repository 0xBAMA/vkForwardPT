#include "third_party/stb/stb_image.h"
#include "third_party/stb/stb_image_write.h"

#include <deque>
#include <vector>
#include <random>
#include <fstream>
#include "third_party/nlohmann/json.hpp"
using json = nlohmann::json;

#include <vk_types.h>

// remap the value from [inLow..inHigh] to [outLow..outHigh]
inline float remap ( float value, float inLow, float inHigh, float outLow, float outHigh ) {
	return outLow + ( value - inLow ) * ( outHigh - outLow ) / ( inHigh - inLow );
}

using glm::vec3;
using glm::vec4;
using glm::bvec4;

#include "spectralData/spectralToolkit.h"

inline glm::vec3 HexToVec3 ( const std::string& hex ) {
	// uint8_t r, g, b;
	// std::stringstream( hex ) >> std::hex >> r >> g >> b;
	// return glm::vec3( r / 255.0f, g / 255.0f, b / 255.0f );

	// Check if the input hex string is valid (should be 6 characters without the #)

	// Extract the RGB components from the hex string
	std::string redHex = hex.substr(0, 2);
	std::string greenHex = hex.substr(2, 2);
	std::string blueHex = hex.substr(4, 2);

	// Convert hex to integers
	int r, g, b;
	std::stringstream ss;

	ss << std::hex << redHex;
	ss >> r;
	ss.clear();

	ss << std::hex << greenHex;
	ss >> g;
	ss.clear();

	ss << std::hex << blueHex;
	ss >> b;

	// Normalize the values to 0-1 range by dividing by 255
	vec3 color;
	color.r = r / 255.0f;
	color.g = g / 255.0f;
	color.b = b / 255.0f;

	return color;
}

#include "third_party/imgui/imgui.h"
#include "third_party/imgui/imgui_impl_vulkan.h"

#include "third_party/Jakob2019Spectral/supplement/rgb2spec.h"
//======================================================================================================================
// for handing out unique identifiers
static int uniqueID { 0 };

// memory associated with the xRite color chip reflectances
static const float** xRiteReflectances = nullptr;

// memory associated with the source PDFs
static int numSourcePDFs = 0;
static const float** sourcePDFs = nullptr;
static const char** sourcePDFLabels = nullptr;

// information about the gel filters
static int numGelFilters = 0;
static const float** gelFilters = nullptr;
static const char** gelFilterLabels = nullptr;
static const char** gelFilterDescriptions = nullptr;
static const glm::vec3* gelPreviewColors = nullptr;

//======================================================================================================================
// light class -> configuration for a single light
class Light {
public:

	Light () {
		// ImGUI needs distinct strings... can use an int, just assign at construction time
		myUniqueID = uniqueID;
		uniqueID++;
	}

	// state flags for the manager
	bool dirtyFlag { false }; // need to call Update() on this light
	bool deleteFlag { false }; // need to delete this light

	// called inside of the light manager ImGui Draw function
	void ImGuiDrawLightInfo () {
	// use myUniqueID in the labels, disambiguates between otherwise identical labels for ImGui
		const std::string lString = std::string( "##" ) + std::to_string( myUniqueID );

		// spectrum preview + xrite checker
			// will just be an image you need to show using the ImGui TextureID
		// ImGui::Image( myTextureID, ImVec2( 386, 256 ) );

			// going to change this to use an atlassed version

		// source PDF picker
		ImGui::Combo( ( std::string( "Light Type" ) + lString ).c_str(), &PDFPick, sourcePDFLabels, numSourcePDFs ); // may eventually do some kind of scaled gaussians for user-configurable RGB triplets...
		dirtyFlag |= ImGui::IsItemEdited();

		ImGui::SameLine(); // pick a random source PDF
		if ( ImGui::Button( ( "Randomize" + lString ).c_str() ) ) {
			static std::mt19937 seedRNG( [] {
				std::random_device rd;
				std::seed_seq seq{  rd(), rd(), rd(), rd(), rd(), rd(), rd(), rd() };
				return std::mt19937( seq );
			} () );
			PDFPick = std::uniform_int_distribution< int >( 0, numSourcePDFs - 1 )( seedRNG );
			dirtyFlag = true; // we changed the light, need to update
		}

		// gel filter list
		for ( int i = 0; i < filterStack.size(); i++ ) {
			ImGui::PushID( i );
			ImGui::Separator();

			// show gel picker
			ImGui::Combo( ( "Gel" + lString ).c_str(), &filterStack[ i ], gelFilterLabels, numGelFilters );
			dirtyFlag |= ImGui::IsItemEdited();

			ImGui::SameLine();
			if ( ImGui::Button( ( "Randomize" + lString ).c_str() ) ) {
				static std::mt19937 seedRNG( [] {
					std::random_device rd;
					std::seed_seq seq{  rd(), rd(), rd(), rd(), rd(), rd(), rd(), rd() };
					return std::mt19937( seq );
				} () );
				filterStack[ i ] = std::uniform_int_distribution< int >( 0, numGelFilters - 1 )( seedRNG );
				dirtyFlag = true;
			}

			ImGui::SameLine();
			if ( ImGui::Button( ( "Remove" + lString ).c_str() ) ) {
				filterStack.erase( filterStack.begin() + i );
				dirtyFlag = true;
			} else { // need to prevent accessing these things if we remove
				// show selected gel preview color
				vec3 col = gelPreviewColors[ filterStack[ i ] ];

				if ( ImGui::ColorButton( ( "##ColorSquare" + lString ).c_str(), ImColor( col.r, col.g, col.b ), ImGuiColorEditFlags_NoAlpha, ImVec2(16, 16 ) ) ) {}
				ImGui::SameLine();

				// show selected gel description
				ImGui::TextWrapped( "%s", gelFilterDescriptions[ filterStack[ i ] ] );
			}
			ImGui::PopID();
		}

		// button to add a new gel to the stack
		if ( ImGui::Button( ( "Add Gel" + lString ).c_str() ) ) {
			filterStack.emplace_back();
			dirtyFlag = true;
		}

		// emitter parameters... tbd

		// option to remove -> set deleteFlag
		if ( ImGui::Button( "Remove" ) ) {
			deleteFlag = true;
		}
	}

	void Update () {
		// compute the current PDF (temporary, not stored outside of this function):
		std::vector< float > PDFScratch;

	// start with the selected light PDF LUT, then apply as many gel filters as there are to apply

	// Starting from the selected source PDF, with no filters applied.
		// We need a curve out of this process representing the filtered light.

		auto LoadPDF = [&] ( int idx ) {
			PDFScratch.clear();
			for ( int i = 0; i < 450; i++ ) {
				PDFScratch.emplace_back( sourcePDFs[ idx ][ i ] );
			}
		};

		auto ApplyFilter = [&] ( int idx ) {
			for ( int i = 0; i < 450; i++ ) {
				PDFScratch[ i ] *= gelFilters[ idx ][ i ];
			}
		};

		auto NormalizePDF = [&] () {
			float max = 0.0f;
			for ( int i = 0; i < 450; i++ ) {
				// first pass, determine the maximum
				max = std::max( max, PDFScratch[ i ] );
			}
			for ( int i = 0; i < 450; i++ ) {
				// second pass we perform the normalization by the observed maximum
				PDFScratch[ i ] /= max;
			}
		};

		// load the selected source PDF
		LoadPDF( PDFPick );
		NormalizePDF();

		// for each selected gel filter
		for ( int i = 0; i < filterStack.size(); i++ ) {
			// apply selected gel filter
			ApplyFilter( filterStack[ i ] );

			// renormalize the PDF
			NormalizePDF();
		}

		// we have the final PDF, now let's get CDF and iCDF
		std::vector< float > cdf;
		float cumSum = 0.0f;
		for ( int x = 0; x < PDFScratch.size(); x++ ) {
			float sum = 0.0f;
			// increment cumulative sum and CDF
			cumSum += PDFScratch[ x ];
			cdf.push_back( cumSum );
		}

		// normalize the CDF values by the final value during CDF sweep
		std::vector< glm::vec2 > CDFpoints;
		for ( int x = 0; x < PDFScratch.size(); x++ ) {
			// compute the inverse CDF with the aid of a series of 2d points along the curve
			// adjust baseline for our desired range -> 380nm to 830nm, we have 450nm of data
			CDFpoints.emplace_back( x + 380, cdf[ x ] / cumSum );
		}

		iCDF.clear();
		for ( int x = 0; x < 1024; x++ ) {
			// each pixel along this strip needs a value of the inverse CDF
			// this is the intersection with the line defined by the set of segments in the array CDFpoints
			float normalizedPosition = ( x + 0.5f ) / 1024.0f;
			for ( int p = 0; p < CDFpoints.size(); p++ )
				if ( p == ( CDFpoints.size() - 1 ) ) {
					iCDF.emplace_back( CDFpoints[ p ].x );
				} else if ( CDFpoints[ p ].y >= normalizedPosition ) {
					iCDF.emplace_back( remap( normalizedPosition, CDFpoints[ p - 1 ].y, CDFpoints[ p ].y, CDFpoints[ p - 1 ].x, CDFpoints[ p ].x ) );
					break;
				}
		}

		// clearing the image
		for ( size_t i = 0; i < previewImageSize.width * previewImageSize.height * 4; i+= 4 ) {
			textureScratch[ i + 0 ] = 0;
			textureScratch[ i + 1 ] = 0;
			textureScratch[ i + 2 ] = 0;
			textureScratch[ i + 3 ] = 255;
		}

		// at the start here, you have the updated light PDF...
			// let's go ahead and compute the preview...
		int xOffset = 0;
		for ( auto& freqBand : PDFScratch ) {
			// we know the PDF value at this location...
			for ( int y = 0; y < previewImageSize.height; y++ ) {
				float fractionalPosition = 1.0f - float( y ) / float( previewImageSize.height );
				if ( fractionalPosition < freqBand ) {
					// we want to use a representative color for the frequency...
					vec3 c = wavelengthColorLDR( xOffset + 380.0f ) * 255.0f;
					setPixel( xOffset, y, c );
				} else {
					// write clear... maybe a grid pattern?
					float xWave = sin( xOffset * 0.5f );
					float yWave = sin( y * 0.5f );
					const float p = 40.0f;
					uint8_t v = std::max( 32.0f * pow( ( 16 + 15 * xWave ) / 32.0f, p ), 32.0f * pow( ( 16 + 15 * yWave ) / 32.0f, p ) );
					setPixel( xOffset, y, vec3( float( v ) ) );
				}
			}
			xOffset++;
		}

		// we know the sRGB xRite color chip reflectances, and the light emission... we need to convolve to get the color result
		vec3 color[ 24 ];
		for ( int chip = 0; chip < 24; chip++ ) {
			// initial accumulation value
			color[ chip ] = vec3( 0.0f );

			// we need to iterate over wavelengths and get an average color value under this illuminant
			for ( int y = 0; y < 450; y++ ) {
				// color[ chip ] += ( wavelengthColorLinear( 380 + y ) * light.PDFScratch[ y ] ) / 450.0f;
				color[ chip ] += 3.5f * glm::clamp( wavelengthColorLinear( 380 + y ) * xRiteReflectances[ chip ][ y ] * PDFScratch[ y ], vec3( 0.0f ), vec3( 1.0f ) ) / 450.0f;
			}
		}

		for ( int x = 0; x < 6; x++ ) {
			for ( int y = 0; y < 4; y++ ) {
				int i = x + 6 * y;
				int bx = 455;
				int by = 5;
				int xS = 13;
				int yS = 12;
				int xM = 2;
				int yM = 2;

				for ( int xo = 0; xo < xS; xo++ ) {
					for ( int yo = 0; yo < yS; yo++ ) {
						setPixel( bx + ( xS + xM ) * x + xo, by + ( yS + yM ) * y + yo, glm::vec3( color[ i ].r * 255, color[ i ].g * 255, color[ i ].b * 255 ) );
					}
				}
			}
		}

		stbi_write_png(
			std::string( "test.png" ).c_str(),
			previewImageSize.width,
			previewImageSize.height,
			4, // RGBA
			textureScratch,
			previewImageSize.width * 4 // stride (bytes per row)
		);

		// compute the iCDF once you have a final PDF, the light manager will need it

		// compute the state of the preview into the scratch memory
			// compute the spectral curve preview
			// compute the xrite color checker
	}

	// spectral distribution
	int PDFPick{ 0 };
	std::vector< int > filterStack;

	// the solved iCDF, needed by the light manager
	std::vector< float > iCDF;

	// unitless, relative brightness
	float brightness{ 1.0f };

	// ImGui textureID thing
	ImTextureID myTextureID;

	// this is just some dimensions I picked, based on the pixel drawings
	static constexpr VkExtent3D previewImageSize { 554, 64 };
	uint8_t textureScratch[ 4 * previewImageSize.width * previewImageSize.height ];
		// texture scratch memory, static allocation -> copied to atlas

	// helper functions for setting pixel color
	inline void setPixel ( int x, int y, const glm::vec3& color ) {
		int index = 4 * ( y * previewImageSize.width + x );

		textureScratch[ index + 0 ] = static_cast<uint8_t>( color.r );
		textureScratch[ index + 1 ] = static_cast<uint8_t>( color.g );
		textureScratch[ index + 2 ] = static_cast<uint8_t>( color.b );
		textureScratch[ index + 3 ] = 255; // constant alpha
	}

private:
	int myUniqueID; // for ImGUI
};

class LightManager {
public:
	LightManager () {
		// create the texture for the

	}

	// you always have a mouse light
	glm::vec2 MouseLocation;
	Light MouseLight;
	std::deque< Light > lights;

	// we have two different importance sampling structures...
		// first is a list of the light spectral iCDFs, in a texture
		// second is for preferentially picking the lights

	// we also have the list of parameters for the lights

	void ImGuiDrawLightList () {
		// configuration for the mouse light

		// and then for a growable list of lights after that

		// after the list is drawn...
			// iterate through and Update() any with the dirtyFlag
			// iterate through and
			// if any needed to call Update(), that means we need to update the GPU resources
	}

	void Update () {
		// construct the light spectral sampling texture from light iCDFs
		// construct the light pick texture from the light brightnesses
		// construct the buffer for the light parameters
	}

};