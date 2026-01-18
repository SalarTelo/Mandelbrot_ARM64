cmake_minimum_required(VERSION 4.1)
project(assembly_test VERSION 0.1 LANGUAGES C CXX ASM OBJC)

set(CMAKE_CXX_STANDARD 20)

# Enable Objective-C for proper compilation
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fPIC")

# Link against Cocoa framework for macOS window support
find_library(COCOA_LIBRARY Cocoa)
find_library(QUARTZCORE_LIBRARY QuartzCore)


# Main assembly app with Objective-C window support
FILE(GLOB_RECURSE ASM_FILES CONFIGURE_DEPENDS src/*.S)
FILE(GLOB_RECURSE C_FILES CONFIGURE_DEPENDS src/*.c)
FILE(GLOB_RECURSE INC_FILES CONFIGURE_DEPENDS include/*.inc)
FILE(GLOB_RECURSE OBJC_FILES CONFIGURE_DEPENDS src/*.m)
add_executable(app ${ASM_FILES} ${C_FILES} ${OBJC_FILES} ${INC_FILES})

target_include_directories(app PRIVATE
    include
)

# Link Cocoa framework for Objective-C support
target_link_libraries(app PRIVATE
    ${COCOA_LIBRARY}
    ${QUARTZCORE_LIBRARY}
)


