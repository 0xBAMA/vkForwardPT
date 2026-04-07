

#include "third_party/stb/stb_image.h"

#include <deque>
#include <vector>
#include <fstream>
#include <third_party/nlohmann/json.hpp>
using json = nlohmann::json;

#include "third_party/imgui/imgui_impl_vulkan.h"

#include "third_party/Jakob2019Spectral/supplement/rgb2spec.h"
//======================================================================================================================
// for handing out unique identifiers
static int uniqueID { 0 };

// what does ImGUI need for the dropdown menus?
	// need the information for the light LUTs
	// need the information for the gel LUTs
	// need the text and the preview swatch for the gel

class Light {
public:

	Light () {
		// ImGUI needs distinct strings... can use an int, just assign at construction time
		myUniqueID = uniqueID;
		uniqueID++;

		// need to create a Vulkan texture for the spectral preview

		// need to create an ImGui textureID for this new image
	}

	// state flags for the manager
	bool dirtyFlag { false }; // need to call Update() on this light
	bool deleteFlag { false }; // need to delete this light

	// called inside of the light manager ImGui Draw function
	void ImGuiDrawLightInfo () {
	// use myUniqueID in the labels e.g. string( "label##" + to_string( myUniqueID ) ).c_str()
		// spectrum preview + xrite checker
		// source PDF picker
		// gel filter list

		// emitter parameters... tbd

		// option to remove -> set deleteFlag
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