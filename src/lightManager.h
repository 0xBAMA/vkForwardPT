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
		std::vector< float > lightPDF;
			// start with the selected light PDF LUT
			// apply as many gel filters as there are to apply

		// compute the iCDF for the light source, the light manager will need it

		// compute the state of the preview into the scratch memory
			// compute the spectral curve preview
			// compute the xrite color checker
			// update the Vulkan texture with the new state
	}

	// spectral distribution
	int PDFPick{ 0 };
	std::vector< int > gelFilters;

	// the solved iCDF
	std::vector< float > iCDF;

	// ImGui textureID thing
	// Vulkan texture
		// texture scratch memory, static allocation


private:
	int myUniqueID;
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