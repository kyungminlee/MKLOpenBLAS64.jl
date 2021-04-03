cmake_minimum_required(VERSION 3.12)

if(DEFINED CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE ${CMAKE_BUILD_TYPE} CACHE STRING "Choose the type of build, options are: None(CMAKE_CXX_FLAGS or CMAKE_C_FLAGS used) Debug Release RelWithDebInfo MinSizeRel.")
else()
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose the type of build, options are: None(CMAKE_CXX_FLAGS or CMAKE_C_FLAGS used) Debug Release RelWithDebInfo MinSizeRel.")
endif()

project(MKLOpenBLAS64)

include("options.cmake")

if (NOT DEFINED MKL_INCLUDE_PATH)
    message(FATAL_ERROR "Define MKL_INCLUDE_PATH")
elseif (NOT DEFINED MKL_LIBRARIES)
    message(FATAL_ERROR "Define MKL_LIBRARIES")
endif()

if (WIN32)
    add_compile_definitions("API_EXPORT=__declspec(dllexport)" "_CRT_SECURE_NO_WARNINGS")
else()
    add_compile_definitions("API_EXPORT=__attribute__((visibility (\"default\")))")
endif()


# ======= build =======
add_library(mklopenblas64_ SHARED "${CMAKE_SOURCE_DIR}/mklopenblas64.c" "${CMAKE_SOURCE_DIR}/mklopenblas64-util.c")
set_target_properties(mklopenblas64_ PROPERTIES PREFIX "lib")  # For Windows

target_include_directories(mklopenblas64_
    PRIVATE
        "${CMAKE_SOURCE_DIR}"
        ${MKL_INCLUDE_PATH}
)
target_link_libraries(mklopenblas64_
    PRIVATE
        ${MKL_LIBRARIES}
)
set_target_properties(
    mklopenblas64_
    PROPERTIES
        C_VISIBILITY_PRESET hidden
)

install(TARGETS mklopenblas64_
    DESTINATION ${CMAKE_INSTALL_PREFIX}
)

if(UNIX)
    target_link_options(mklopenblas64_ PUBLIC "LINKER:--exclude-libs,ALL")
elseif(WIN32)

elseif(APPLE)

endif()
