########################################################################
# Install the aggregate build into an empty stage prefix (cmake -P).
#
# Required: -DBUILD_DIR=<PothosBase build dir> -DPREFIX=<stage prefix>
# Optional: -DCONFIG=<configuration> for multi-config generators
#
# cmake --install only adds and overwrites files. Thus this script removes
# the old stage prefix first: modules of an earlier install (a toolkit that
# is now off, a module that a clone had, an old ABI dir) must not get into
# the tests. For safety, it removes only a dir in BUILD_DIR or a dir with
# the marker file that it writes after each install.
########################################################################
cmake_minimum_required(VERSION 3.25)
foreach(var BUILD_DIR PREFIX)
    if (NOT DEFINED ${var})
        message(FATAL_ERROR "PothosBaseStage: ${var} is not set")
    endif ()
endforeach()
foreach(var BUILD_DIR PREFIX)
    cmake_path(ABSOLUTE_PATH ${var} BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" NORMALIZE)
endforeach()
set(marker "${PREFIX}/.pothos-base-stage")

if (EXISTS "${PREFIX}")
    cmake_path(IS_PREFIX BUILD_DIR "${PREFIX}" NORMALIZE in_build_dir)
    file(GLOB entries "${PREFIX}/*" "${PREFIX}/.*")
    if (entries AND NOT in_build_dir AND NOT EXISTS "${marker}")
        message(FATAL_ERROR "PothosBaseStage: ${PREFIX} is not a stage prefix "
            "(not in ${BUILD_DIR}, no marker file): it is not removed")
    endif ()
    file(REMOVE_RECURSE "${PREFIX}")
endif ()

set(config_args)
if (CONFIG)
    set(config_args --config "${CONFIG}")
endif ()
execute_process(COMMAND ${CMAKE_COMMAND} --install "${BUILD_DIR}" --prefix "${PREFIX}" ${config_args}
    RESULT_VARIABLE rc)
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "PothosBaseStage: cmake --install failed: ${rc}")
endif ()
file(WRITE "${marker}" "")
