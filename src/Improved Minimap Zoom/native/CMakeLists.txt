# 3.18: Plugins/CMakeLists.txt uses FetchContent_Declare's
# SOURCE_SUBDIR, which was added in 3.18. The root minimum governs the whole
# project, so it has to be raised here too or the declared floor is a lie.
cmake_minimum_required(VERSION 3.18)
project(ImprovedMinimapZoomNative LANGUAGES CXX)

# Add the Plugins subdirectory that contains the actual plugin target
add_subdirectory(Plugins)
