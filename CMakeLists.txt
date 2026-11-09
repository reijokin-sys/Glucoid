# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.22)
project(GlucoidNative LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.10 REQUIRED COMPONENTS Core Network Qml Quick QuickTest Test)
find_package(CURL 7.85 REQUIRED)
add_library(glucoidnetwork MODULE native/plugin.cpp native/secureclient.cpp native/wireguard.cpp)
target_link_libraries(glucoidnetwork PRIVATE Qt6::Core Qt6::Network Qt6::Qml CURL::libcurl)
target_compile_options(glucoidnetwork PRIVATE -Wall -Wextra -Wpedantic)
set_target_properties(glucoidnetwork PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml-native")
include(CTest)
if(BUILD_TESTING)
  add_executable(native-probe tests/native-probe.cpp native/secureclient.cpp native/wireguard.cpp)
  target_include_directories(native-probe PRIVATE native)
  target_compile_definitions(native-probe PRIVATE GLUCOID_TESTING)
  target_link_libraries(native-probe PRIVATE Qt6::Core Qt6::Network CURL::libcurl)
  target_compile_options(native-probe PRIVATE -Wall -Wextra -Wpedantic)
endif()
find_package(Python3 REQUIRED COMPONENTS Interpreter)
add_custom_target(stage-native ALL
  COMMAND ${Python3_EXECUTABLE} "${CMAKE_SOURCE_DIR}/native/stage.py"
    --project "${CMAKE_SOURCE_DIR}" --library $<TARGET_FILE:glucoidnetwork>
    --qt-version "${Qt6_VERSION}" --curl-version "${CURL_VERSION_STRING}"
  DEPENDS glucoidnetwork
  VERBATIM)
