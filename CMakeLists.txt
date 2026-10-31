########################################################################
# PothosBase: the aggregate build of the Pothos core and its toolkits.
# The core and each toolkit are git submodules (branch pothos2), built in
# one CMake tree with add_subdirectory. A toolkit finds the core with
# find_package(Pothos) through the in-tree configuration of the core.
# POTHOS_BASE_<NAME>_DIR gives a local clone in place of a submodule.
########################################################################
cmake_minimum_required(VERSION 3.25)
project(PothosBase C CXX)

#one compilation database for the core and all toolkits (clangd)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(POTHOS_BASE_WARNINGS_AS_ERRORS "Treat compiler warnings as errors in all repositories (GCC and Clang)" OFF)
option(POTHOS_BASE_BUILD_TESTS "Register the CTest tests of the aggregate build" ${PROJECT_IS_TOP_LEVEL})

#the toolkits in build order (the core is always first)
set(pothos_base_all_toolkits blocks comms widgets soapy plotters flow audio)
foreach(toolkit IN LISTS pothos_base_all_toolkits)
    string(TOUPPER ${toolkit} TOOLKIT)
    option(POTHOS_BASE_WITH_${TOOLKIT} "Build the ${toolkit} toolkit" ON)
endforeach()

#the comms, soapy, plotters and audio self-tests use blocks of PothosBlocks (feeder, collector,
#copier, pacer), and the flow smoke test checks /blocks/copier in the block cache
foreach(toolkit comms soapy plotters flow audio)
    string(TOUPPER ${toolkit} TOOLKIT)
    if (POTHOS_BASE_BUILD_TESTS AND POTHOS_BASE_WITH_${TOOLKIT} AND NOT POTHOS_BASE_WITH_BLOCKS)
        message(FATAL_ERROR "PothosBase: the ${toolkit} tests need blocks. "
            "Set POTHOS_BASE_WITH_BLOCKS=ON, or POTHOS_BASE_WITH_${TOOLKIT}=OFF, or POTHOS_BASE_BUILD_TESTS=OFF.")
    endif ()
endforeach()

#the plotters make /comms/wave_trigger at run time
if (POTHOS_BASE_WITH_PLOTTERS AND NOT POTHOS_BASE_WITH_COMMS)
    message(FATAL_ERROR "PothosBase: plotters needs comms (the plotters use /comms/wave_trigger). "
        "Set POTHOS_BASE_WITH_COMMS=ON, or POTHOS_BASE_WITH_PLOTTERS=OFF.")
endif ()

#the warnings option of each repository (an option() of the subproject
#takes the value of a normal variable: CMP0077)
set(POTHOS_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
set(BLOCKS_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
set(COMMS_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
set(WIDGETS_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
set(SOAPY_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
set(PLOTTERS_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
set(FLOW_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
set(AUDIO_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
#the flow smoke test executable; base.flow runs it from the stage prefix
set(FLOW_BUILD_SMOKE_TEST ${POTHOS_BASE_BUILD_TESTS})

########################################################################
# pothos_base_add(<name>): add the repository <name> from the dir in
# POTHOS_BASE_<NAME>_DIR (default: the submodule dir <name>)
########################################################################
set(pothos_base_local_clones)
find_package(Git QUIET)

function(pothos_base_add name)
    string(TOUPPER ${name} NAME)
    set(default_dir "${PROJECT_SOURCE_DIR}/${name}")
    set(POTHOS_BASE_${NAME}_DIR "${default_dir}" CACHE PATH
        "Source dir of ${name} (default: the submodule; give a local clone to build it in place of the submodule)")
    set(dir "${POTHOS_BASE_${NAME}_DIR}")
    if (NOT dir)
        set(dir "${default_dir}")
    endif ()
    cmake_path(ABSOLUTE_PATH dir NORMALIZE)
    cmake_path(ABSOLUTE_PATH default_dir NORMALIZE)

    if (NOT EXISTS "${dir}/CMakeLists.txt")
        if (dir STREQUAL default_dir)
            message(FATAL_ERROR "PothosBase: the submodule ${name} is not checked out. "
                "Run: git submodule update --init ${name}")
        endif ()
        message(FATAL_ERROR "PothosBase: POTHOS_BASE_${NAME}_DIR=${dir} has no CMakeLists.txt.")
    endif ()

    if (NOT dir STREQUAL default_dir)
        set(describe "")
        if (GIT_FOUND)
            execute_process(COMMAND ${GIT_EXECUTABLE} -C "${dir}" describe --always --dirty
                OUTPUT_VARIABLE describe OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
        endif ()
        message(STATUS "PothosBase: ${name} from the local clone ${dir} ${describe}")
        set(pothos_base_local_clones ${pothos_base_local_clones} ${name} PARENT_SCOPE)
    endif ()

    #the resolved dir for the tests (an empty option means the submodule)
    set(pothos_base_${name}_dir "${dir}" PARENT_SCOPE)

    #the source can be outside this tree: always give the binary dir
    add_subdirectory("${dir}" "${name}")
endfunction()

########################################################################
# The repositories
########################################################################
pothos_base_add(core)

set(POTHOS_BASE_TOOLKITS)
foreach(toolkit IN LISTS pothos_base_all_toolkits)
    string(TOUPPER ${toolkit} TOOLKIT)
    if (POTHOS_BASE_WITH_${TOOLKIT})
        pothos_base_add(${toolkit})
        list(APPEND POTHOS_BASE_TOOLKITS ${toolkit})
    endif ()
endforeach()

if (pothos_base_local_clones)
    list(JOIN pothos_base_local_clones ", " clones_text)
    message(WARNING "PothosBase: this build uses local clones (${clones_text}): "
        "it is not the fixed set of the submodule pointers.")
endif ()

########################################################################
# Tests: install the whole tree into one stage prefix, check that every
# module loads, then run all self-tests (core and toolkits) from it
########################################################################
if (POTHOS_BASE_BUILD_TESTS)
    enable_testing()
    set(POTHOS_BASE_SELFTEST_TIMEOUT 1800 CACHE STRING "Timeout in seconds for the self-tests")
    set(stage_dir ${PROJECT_BINARY_DIR}/stage)
    #the stage prefix starts empty: modules of an earlier install (a toolkit
    #that is now off, an old ABI dir) must not get into the tests
    add_test(NAME base.stage
        COMMAND ${CMAKE_COMMAND}
            -DBUILD_DIR=${PROJECT_BINARY_DIR}
            -DPREFIX=${stage_dir}
            -DCONFIG=$<CONFIG>
            -P ${PROJECT_SOURCE_DIR}/cmake/PothosBaseStage.cmake)
    set_tests_properties(base.stage PROPERTIES FIXTURES_SETUP base_stage)

    #flow is an application without self-tests: base.flow runs its smoke test
    set(pothos_base_selftest_toolkits ${POTHOS_BASE_TOOLKITS})
    list(REMOVE_ITEM pothos_base_selftest_toolkits flow)
    foreach(mode modules selftests)
        if (mode STREQUAL "modules")
            set(mode_toolkits ${POTHOS_BASE_TOOLKITS})
        else ()
            set(mode_toolkits ${pothos_base_selftest_toolkits})
        endif ()
        add_test(NAME base.${mode}
            COMMAND ${CMAKE_COMMAND}
                -DPREFIX=${stage_dir}
                -DTEST_HOME_DIR=${PROJECT_BINARY_DIR}/test-home
                -DBINDIR=${CMAKE_INSTALL_BINDIR}
                -DLIBDIR=${CMAKE_INSTALL_LIBDIR}
                -DCORE_DIR=${pothos_base_core_dir}
                "-DTOOLKITS=${mode_toolkits}"
                -DMODE=${mode}
                -P ${PROJECT_SOURCE_DIR}/cmake/PothosBaseSelfTests.cmake)
        #the widgets and the plotters need no display: Qt uses the offscreen platform;
        #the audio tests need no sound card: miniaudio uses its null backend
        set_tests_properties(base.${mode} PROPERTIES
            FIXTURES_REQUIRED base_stage
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;POTHOS_AUDIO_BACKEND=null")
    endforeach()
    set_tests_properties(base.selftests PROPERTIES
        DEPENDS base.modules
        TIMEOUT ${POTHOS_BASE_SELFTEST_TIMEOUT})

    #the flow smoke test: the main window of flow against the stage prefix
    if (POTHOS_BASE_WITH_FLOW)
        add_test(NAME base.flow
            COMMAND ${CMAKE_COMMAND}
                -DPREFIX=${stage_dir}
                -DTEST_HOME_DIR=${PROJECT_BINARY_DIR}/test-home-flow
                -DBINDIR=${CMAKE_INSTALL_BINDIR}
                -DLIBDIR=${CMAKE_INSTALL_LIBDIR}
                -DSTAGE_BINDIR=${stage_dir}/${CMAKE_INSTALL_BINDIR}
                -DSMOKE_TEST=$<TARGET_FILE:PothosFlowSmokeTest>
                -P ${pothos_base_flow_dir}/cmake/PothosRunFlowSmokeTest.cmake)
        #the main window of flow starts a server on the fixed locator port of Pothos
        set_tests_properties(base.flow PROPERTIES
            FIXTURES_REQUIRED base_stage
            DEPENDS base.modules
            RESOURCE_LOCK pothos_locator_port
            TIMEOUT 240)
    endif ()

    #the environment of the stage prefix for a developer shell (debugger)
    if (APPLE)
        set(library_path_var DYLD_LIBRARY_PATH)
    else ()
        set(library_path_var LD_LIBRARY_PATH)
    endif ()
    configure_file(cmake/pothos-env.sh.in ${PROJECT_BINARY_DIR}/pothos-env.sh @ONLY)
    configure_file(cmake/pothos-env.ps1.in ${PROJECT_BINARY_DIR}/pothos-env.ps1 @ONLY)
endif ()
