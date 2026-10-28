########################################################################
# Configure checks of the aggregate build (cmake -P script).
#
# Required: -DSRC=<PothosBase source> -DWORK=<scratch dir>
# Optional: -DGENERATOR=<generator> (default Ninja)
#           -DTOOLCHAIN=<toolchain file> -DPREFIX_PATH=<|-separated prefixes>
#           -DBUILD_TYPE=<build type> to find the dependencies as the calling
#           build does
#           -DBLOCKS_CLONE=<local clone of PothosBlocks> for the cases with
#           a local clone (skipped without it)
#
# Cases:
#  - default: the submodules; no warning about local clones, no CMake
#    policy warning
#  - missing: a clone without --recursive (empty submodule dirs) stops with
#    the git submodule command
#  - bad_dir: a source dir option to a dir that does not exist stops with
#    the path
#  - override: a local clone of blocks; a status line with its path, one
#    warning about local clones, no CMake policy warning
#  - override_reset: the same build dir with -U of the option goes back to
#    the submodule, and the warning goes away
#  - without_blocks: POTHOS_BASE_WITH_BLOCKS=OFF configures
#  - empty_core_dir: an empty POTHOS_BASE_CORE_DIR means the submodule,
#    also for the tests (CORE_DIR of the test commands)
########################################################################
cmake_minimum_required(VERSION 3.25)
foreach(var SRC WORK)
    if (NOT DEFINED ${var})
        message(FATAL_ERROR "configure_checks: ${var} is not set")
    endif ()
endforeach()
if (NOT GENERATOR)
    set(GENERATOR Ninja)
endif ()
set(override_warning "not the fixed set of the submodule pointers")

#an initial cache: a list of prefixes stays one value
file(MAKE_DIRECTORY "${WORK}")
set(dependency_args)
if (TOOLCHAIN OR PREFIX_PATH)
    string(REPLACE "|" ";" prefix_path "${PREFIX_PATH}")
    file(WRITE "${WORK}/dependencies.cmake"
        "set(CMAKE_TOOLCHAIN_FILE \"${TOOLCHAIN}\" CACHE FILEPATH \"\")\n"
        "set(CMAKE_PREFIX_PATH \"${prefix_path}\" CACHE STRING \"\")\n"
        "set(CMAKE_BUILD_TYPE \"${BUILD_TYPE}\" CACHE STRING \"\")\n")
    set(dependency_args -C "${WORK}/dependencies.cmake")
endif ()

#configure(<case> <source dir> <build dir> <FRESH|KEEP> <args...>)
#sets case_rc and case_out (stdout and stderr) in the parent scope
function(configure name source build mode)
    if (mode STREQUAL "FRESH")
        file(REMOVE_RECURSE "${build}")
    endif ()
    execute_process(
        COMMAND ${CMAKE_COMMAND} -S "${source}" -B "${build}" -G "${GENERATOR}"
            ${dependency_args} ${ARGN}
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    set(case_rc ${rc} PARENT_SCOPE)
    #CMake wraps long messages: compare with all white space as one space
    string(REGEX REPLACE "[ \t\r\n]+" " " text "${out} ${err}")
    set(case_out "${text}" PARENT_SCOPE)
endfunction()

function(fail name why)
    message(FATAL_ERROR "configure_checks: case ${name}: ${why}\n${case_out}")
endfunction()

function(expect_success name)
    if (NOT case_rc EQUAL 0)
        fail(${name} "configure failed (${case_rc})")
    endif ()
endfunction()

function(expect_failure name)
    if (case_rc EQUAL 0)
        fail(${name} "configure did not fail")
    endif ()
endfunction()

function(expect_text name text)
    string(FIND "${case_out}" "${text}" pos)
    if (pos EQUAL -1)
        fail(${name} "the output does not contain \"${text}\"")
    endif ()
endfunction()

function(expect_no_text name text)
    string(FIND "${case_out}" "${text}" pos)
    if (NOT pos EQUAL -1)
        fail(${name} "the output contains \"${text}\"")
    endif ()
endfunction()

#default
configure(default "${SRC}" "${WORK}/default" FRESH)
expect_success(default)
expect_no_text(default "${override_warning}")
expect_no_text(default "CMake Warning (policy)")
message(STATUS "configure_checks: default OK")

#missing: the top-level files of the source with empty submodule dirs
set(missing_src "${WORK}/src-missing")
file(REMOVE_RECURSE "${missing_src}")
file(MAKE_DIRECTORY "${missing_src}/core" "${missing_src}/blocks")
foreach(item CMakeLists.txt conanfile.txt cmake)
    if (EXISTS "${SRC}/${item}")
        file(COPY "${SRC}/${item}" DESTINATION "${missing_src}")
    endif ()
endforeach()
configure(missing "${missing_src}" "${WORK}/missing" FRESH)
expect_failure(missing)
expect_text(missing "git submodule update --init core")
message(STATUS "configure_checks: missing OK")

#bad_dir
configure(bad_dir "${SRC}" "${WORK}/bad_dir" FRESH "-DPOTHOS_BASE_CORE_DIR=${WORK}/nonexistent")
expect_failure(bad_dir)
expect_text(bad_dir "${WORK}/nonexistent")
message(STATUS "configure_checks: bad_dir OK")

#override and override_reset
if (BLOCKS_CLONE)
    configure(override "${SRC}" "${WORK}/override" FRESH "-DPOTHOS_BASE_BLOCKS_DIR=${BLOCKS_CLONE}")
    expect_success(override)
    expect_text(override "${BLOCKS_CLONE}")
    expect_text(override "${override_warning}")
    expect_no_text(override "CMake Warning (policy)")
    message(STATUS "configure_checks: override OK")

    configure(override_reset "${SRC}" "${WORK}/override" KEEP "-UPOTHOS_BASE_BLOCKS_DIR")
    expect_success(override_reset)
    expect_no_text(override_reset "${override_warning}")
    message(STATUS "configure_checks: override_reset OK")
else ()
    message(STATUS "configure_checks: override, override_reset skipped (no BLOCKS_CLONE)")
endif ()

#without_blocks
configure(without_blocks "${SRC}" "${WORK}/without_blocks" FRESH "-DPOTHOS_BASE_WITH_BLOCKS=OFF")
expect_success(without_blocks)
message(STATUS "configure_checks: without_blocks OK")

#empty_core_dir
configure(empty_core_dir "${SRC}" "${WORK}/empty_core_dir" FRESH "-DPOTHOS_BASE_CORE_DIR=")
expect_success(empty_core_dir)
file(READ "${WORK}/empty_core_dir/CTestTestfile.cmake" case_out)
expect_text(empty_core_dir "-DCORE_DIR=${SRC}/core\"")
message(STATUS "configure_checks: empty_core_dir OK")

message(STATUS "configure_checks: all cases passed")
