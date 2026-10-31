########################################################################
# Run the checks of the aggregate build on a staged install (cmake -P).
# It uses the test environment of the core (PothosTestEnv.cmake, not a
# copy) and adds the checks that the core runner does not do.
#
# Required: -DPREFIX=<staged install> -DTEST_HOME_DIR=<isolated user dirs>
#           -DBINDIR=<relative bin dir> -DLIBDIR=<relative lib dir>
#           -DCORE_DIR=<core source> -DTOOLKITS=<;-list of toolkit names>
#           -DMODE=modules|selftests
# Optional: -DTEST_PATH=<plugin path> to run a single self test (selftests)
#
# MODE=modules: each toolkit has module files, and each module file loads
#   (PothosUtil --load-module). A module that does not load only gives a log
#   message in a normal run, and its tests are then missing.
# MODE=selftests: all modules come from the prefix, then the self-tests
#   run; without TEST_PATH, each toolkit must give at least one test
#   (--self-tests on a path without tests passes with 0 tests).
########################################################################
cmake_minimum_required(VERSION 3.25)
foreach(var PREFIX TEST_HOME_DIR BINDIR LIBDIR CORE_DIR TOOLKITS MODE)
    if (NOT DEFINED ${var})
        message(FATAL_ERROR "PothosBaseSelfTests: ${var} is not set")
    endif ()
endforeach()

#relative paths are relative to the current dir (cmake -P): the loader
#prints absolute module paths, so the prefix must be absolute too
foreach(var PREFIX TEST_HOME_DIR CORE_DIR)
    cmake_path(ABSOLUTE_PATH ${var} BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" NORMALIZE)
endforeach()

include(${CORE_DIR}/cmake/PothosTestEnv.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/PothosBaseModulePaths.cmake)
pothos_test_env("${PREFIX}" "${TEST_HOME_DIR}" "${BINDIR}" "${LIBDIR}")
#no display and no sound card: Qt uses the offscreen platform, miniaudio its
#null backend (the CTest tests and a direct run of this script are the same)
if (NOT DEFINED ENV{QT_QPA_PLATFORM})
    set(ENV{QT_QPA_PLATFORM} "offscreen")
endif ()
if (NOT DEFINED ENV{POTHOS_AUDIO_BACKEND})
    set(ENV{POTHOS_AUDIO_BACKEND} "null")
endif ()
#only the modules of the prefix
unset(ENV{POTHOS_PLUGIN_PATH})

set(util "${PREFIX}/${BINDIR}/PothosUtil")
#the module suffix of the core (MODULE_EXT): .so also on macOS
if (WIN32)
    set(util "${PREFIX}/${BINDIR}/PothosUtil.exe")
    set(module_glob "*.dll")
else ()
    set(module_glob "*.so")
endif ()

if (MODE STREQUAL "modules")
    foreach(toolkit IN LISTS TOOLKITS)
        file(GLOB toolkit_modules "${PREFIX}/${LIBDIR}/Pothos/modules*/${toolkit}/${module_glob}")
        if (NOT toolkit_modules)
            message(FATAL_ERROR "PothosBase: no modules of ${toolkit} under ${PREFIX}/${LIBDIR}/Pothos")
        endif ()
    endforeach()
    file(GLOB_RECURSE modules "${PREFIX}/${LIBDIR}/Pothos/${module_glob}")
    list(SORT modules)
    foreach(module IN LISTS modules)
        execute_process(COMMAND "${util}" "--load-module=${module}"
            RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
        if (NOT rc EQUAL 0)
            message(FATAL_ERROR "PothosBase: the module ${module} does not load (${rc}):\n${out}${err}")
        endif ()
    endforeach()
    list(LENGTH modules count)
    message(STATUS "PothosBase: all ${count} modules load")
    return()
endif ()

if (NOT MODE STREQUAL "selftests")
    message(FATAL_ERROR "PothosBaseSelfTests: MODE must be modules or selftests, not ${MODE}")
endif ()

execute_process(COMMAND "${util}" --list-modules
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "PothosUtil --list-modules failed (${rc}):\n${out}${err}")
endif ()
pothos_base_check_module_paths("${out}" "${PREFIX}")

if (TEST_PATH)
    set(args --self-test1 "${TEST_PATH}")
else ()
    set(args --self-tests)
endif ()
#the output goes to the log at once (a test that hangs until the timeout
#is then visible) and is also kept for the checks below
execute_process(COMMAND "${util}" ${args}
    RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err
    ECHO_OUTPUT_VARIABLE ECHO_ERROR_VARIABLE)
if (NOT rc EQUAL 0)
    message(FATAL_ERROR "PothosUtil ${args} failed: ${rc}")
endif ()

if (NOT TEST_PATH)
    foreach(toolkit IN LISTS TOOLKITS)
        string(FIND "${out}" "Testing /${toolkit}/tests/" pos)
        if (pos EQUAL -1)
            message(FATAL_ERROR "PothosBase: no self-tests under /${toolkit}/tests")
        endif ()
    endforeach()
endif ()
