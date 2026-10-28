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
set(pothos_base_all_toolkits blocks)
foreach(toolkit IN LISTS pothos_base_all_toolkits)
    string(TOUPPER ${toolkit} TOOLKIT)
    option(POTHOS_BASE_WITH_${TOOLKIT} "Build the ${toolkit} toolkit" ON)
endforeach()

#the warnings option of each repository (an option() of the subproject
#takes the value of a normal variable: CMP0077)
set(POTHOS_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
set(BLOCKS_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})
set(COMMS_WARNINGS_AS_ERRORS ${POTHOS_BASE_WARNINGS_AS_ERRORS})

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
    cmake_path(ABSOLUTE_PATH POTHOS_BASE_CORE_DIR NORMALIZE OUTPUT_VARIABLE core_dir)

    add_test(NAME base.stage
        COMMAND ${CMAKE_COMMAND} --install ${PROJECT_BINARY_DIR} --prefix ${stage_dir} --config $<CONFIG>)
    set_tests_properties(base.stage PROPERTIES FIXTURES_SETUP base_stage)

    foreach(mode modules selftests)
        add_test(NAME base.${mode}
            COMMAND ${CMAKE_COMMAND}
                -DPREFIX=${stage_dir}
                -DTEST_HOME_DIR=${PROJECT_BINARY_DIR}/test-home
                -DBINDIR=${CMAKE_INSTALL_BINDIR}
                -DLIBDIR=${CMAKE_INSTALL_LIBDIR}
                -DCORE_DIR=${core_dir}
                "-DTOOLKITS=${POTHOS_BASE_TOOLKITS}"
                -DMODE=${mode}
                -P ${PROJECT_SOURCE_DIR}/cmake/PothosBaseSelfTests.cmake)
        set_tests_properties(base.${mode} PROPERTIES FIXTURES_REQUIRED base_stage)
    endforeach()
    set_tests_properties(base.selftests PROPERTIES
        DEPENDS base.modules
        TIMEOUT ${POTHOS_BASE_SELFTEST_TIMEOUT})
endif ()
