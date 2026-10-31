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
#  - comms_without_blocks: comms with the tests on and blocks off stops:
#    the comms tests need blocks
#  - empty_core_dir: an empty POTHOS_BASE_CORE_DIR means the submodule,
#    also for the tests (CORE_DIR of the test commands)
#  - without_widgets: POTHOS_BASE_WITH_WIDGETS=OFF configures without Qt
#  - widgets_without_qt: widgets without Qt 6 stops with the Qt message of
#    widgets (no build without the module)
#  - without_soapy: POTHOS_BASE_WITH_SOAPY=OFF configures without SoapySDR
#  - soapy_without_soapysdr: soapy without SoapySDR stops with the message
#    of soapy (no build without the modules)
#  - soapy_without_blocks: soapy with the tests on and blocks off stops:
#    the soapy tests need blocks
#  - without_plotters: POTHOS_BASE_WITH_PLOTTERS=OFF configures without Qwt
#  - plotters_without_qwt: plotters without Qwt stops with the Qwt message
#    of plotters (no build without the modules)
#  - plotters_without_comms: plotters with comms off stops: the plotters
#    use /comms/wave_trigger
#  - flow_without_blocks: flow with the tests on and blocks off stops: the
#    flow smoke test checks the blocks in the block cache
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

#without_blocks (comms, soapy, plotters and flow are off too: their tests need blocks)
configure(without_blocks "${SRC}" "${WORK}/without_blocks" FRESH
    "-DPOTHOS_BASE_WITH_BLOCKS=OFF" "-DPOTHOS_BASE_WITH_COMMS=OFF" "-DPOTHOS_BASE_WITH_SOAPY=OFF"
    "-DPOTHOS_BASE_WITH_PLOTTERS=OFF" "-DPOTHOS_BASE_WITH_FLOW=OFF")
expect_success(without_blocks)
message(STATUS "configure_checks: without_blocks OK")

#comms_without_blocks
configure(comms_without_blocks "${SRC}" "${WORK}/comms_without_blocks" FRESH
    "-DPOTHOS_BASE_WITH_BLOCKS=OFF" "-DPOTHOS_BASE_WITH_SOAPY=OFF")
expect_failure(comms_without_blocks)
expect_text(comms_without_blocks "the comms tests need blocks")
message(STATUS "configure_checks: comms_without_blocks OK")

#empty_core_dir
configure(empty_core_dir "${SRC}" "${WORK}/empty_core_dir" FRESH "-DPOTHOS_BASE_CORE_DIR=")
expect_success(empty_core_dir)
file(READ "${WORK}/empty_core_dir/CTestTestfile.cmake" case_out)
expect_text(empty_core_dir "-DCORE_DIR=${SRC}/core\"")
message(STATUS "configure_checks: empty_core_dir OK")

#without_widgets (no Qt is necessary; plotters and flow need Qt too)
configure(without_widgets "${SRC}" "${WORK}/without_widgets" FRESH
    "-DPOTHOS_BASE_WITH_WIDGETS=OFF" "-DPOTHOS_BASE_WITH_PLOTTERS=OFF" "-DPOTHOS_BASE_WITH_FLOW=OFF"
    "-DCMAKE_DISABLE_FIND_PACKAGE_Qt6=ON")
expect_success(without_widgets)
message(STATUS "configure_checks: without_widgets OK")

#widgets_without_qt
configure(widgets_without_qt "${SRC}" "${WORK}/widgets_without_qt" FRESH "-DCMAKE_DISABLE_FIND_PACKAGE_Qt6=ON")
expect_failure(widgets_without_qt)
expect_text(widgets_without_qt "Qt 6 (>= 6.5) with the Widgets component is missing")
message(STATUS "configure_checks: widgets_without_qt OK")

#without_soapy (no SoapySDR is necessary)
configure(without_soapy "${SRC}" "${WORK}/without_soapy" FRESH
    "-DPOTHOS_BASE_WITH_SOAPY=OFF" "-DCMAKE_DISABLE_FIND_PACKAGE_SoapySDR=ON")
expect_success(without_soapy)
message(STATUS "configure_checks: without_soapy OK")

#soapy_without_soapysdr
configure(soapy_without_soapysdr "${SRC}" "${WORK}/soapy_without_soapysdr" FRESH "-DCMAKE_DISABLE_FIND_PACKAGE_SoapySDR=ON")
expect_failure(soapy_without_soapysdr)
expect_text(soapy_without_soapysdr "PothosSoapy: missing build dependencies: SoapySDR")
message(STATUS "configure_checks: soapy_without_soapysdr OK")

#soapy_without_blocks
configure(soapy_without_blocks "${SRC}" "${WORK}/soapy_without_blocks" FRESH
    "-DPOTHOS_BASE_WITH_BLOCKS=OFF" "-DPOTHOS_BASE_WITH_COMMS=OFF")
expect_failure(soapy_without_blocks)
expect_text(soapy_without_blocks "the soapy tests need blocks")
message(STATUS "configure_checks: soapy_without_blocks OK")

#without_plotters (no Qwt is necessary)
configure(without_plotters "${SRC}" "${WORK}/without_plotters" FRESH
    "-DPOTHOS_BASE_WITH_PLOTTERS=OFF" "-DCMAKE_DISABLE_FIND_PACKAGE_Qwt=ON")
expect_success(without_plotters)
message(STATUS "configure_checks: without_plotters OK")

#plotters_without_qwt
configure(plotters_without_qwt "${SRC}" "${WORK}/plotters_without_qwt" FRESH "-DCMAKE_DISABLE_FIND_PACKAGE_Qwt=ON")
expect_failure(plotters_without_qwt)
expect_text(plotters_without_qwt "PothosPlotters: Qwt (>= 6.3.0) for Qt 6 is missing")
message(STATUS "configure_checks: plotters_without_qwt OK")

#plotters_without_comms
configure(plotters_without_comms "${SRC}" "${WORK}/plotters_without_comms" FRESH "-DPOTHOS_BASE_WITH_COMMS=OFF")
expect_failure(plotters_without_comms)
expect_text(plotters_without_comms "plotters needs comms")
message(STATUS "configure_checks: plotters_without_comms OK")

#flow_without_blocks
configure(flow_without_blocks "${SRC}" "${WORK}/flow_without_blocks" FRESH
    "-DPOTHOS_BASE_WITH_BLOCKS=OFF" "-DPOTHOS_BASE_WITH_COMMS=OFF" "-DPOTHOS_BASE_WITH_SOAPY=OFF"
    "-DPOTHOS_BASE_WITH_PLOTTERS=OFF")
expect_failure(flow_without_blocks)
expect_text(flow_without_blocks "the flow tests need blocks")
message(STATUS "configure_checks: flow_without_blocks OK")

message(STATUS "configure_checks: all cases passed")
