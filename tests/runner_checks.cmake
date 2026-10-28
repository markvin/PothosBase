########################################################################
# Checks of cmake/PothosBaseSelfTests.cmake (cmake -P script).
#
# Required: -DSTAGE=<staged prefix of a PothosBase build> -DWORK=<scratch dir>
#           -DCORE_DIR=<core source> -DTOOLKITS=<;-list of toolkit names>
#           -DBUILD_DIR=<the PothosBase build dir of the stage> for stage_clean
#           (skipped without it)
# Optional: -DBINDIR=<bin dir> (default bin) -DLIBDIR=<lib dir> (default lib)
#           -DQUICK_TEST=<one self-test path> for the cases that need only
#           one test (default /blocks/tests/test_copier_domain_crossing)
#           -DENV_SCRIPT=<build/pothos-env.sh> for the env case (not on
#           Windows; skipped without it)
#
# Cases:
#  - good: MODE=modules and MODE=selftests pass on the stage
#  - broken_module: a file that is not a module in a toolkit module dir
#    fails MODE=modules with its name
#  - foreign_plugin_path: POTHOS_PLUGIN_PATH in the environment does not
#    get modules into the run (the script unsets it)
#  - foreign_module: pothos_base_check_module_paths() stops on a module
#    path outside the prefix, and passes when all are inside
#  - no_toolkit_tests: a toolkit without self-tests fails MODE=selftests
#  - relative_prefix: a relative PREFIX (from the current dir) works
#  - stage_clean: cmake/PothosBaseStage.cmake removes an old stage prefix
#    (it has the marker file) before the install, and does not remove a
#    dir without the marker
#  - env: after "source pothos-env.sh", PothosUtil runs a self-test of the
#    stage, and POTHOS_PLUGIN_PATH is not set
########################################################################
cmake_minimum_required(VERSION 3.25)
foreach(var STAGE WORK CORE_DIR TOOLKITS)
    if (NOT DEFINED ${var})
        message(FATAL_ERROR "runner_checks: ${var} is not set")
    endif ()
endforeach()
if (NOT BINDIR)
    set(BINDIR bin)
endif ()
if (NOT LIBDIR)
    set(LIBDIR lib)
endif ()
if (NOT QUICK_TEST)
    set(QUICK_TEST /blocks/tests/test_copier_domain_crossing)
endif ()
set(script "${CMAKE_CURRENT_LIST_DIR}/../cmake/PothosBaseSelfTests.cmake")
file(MAKE_DIRECTORY "${WORK}")

#run_script(<prefix> <toolkits> <mode> [<test path>]): sets run_rc, run_out
function(run_script prefix toolkits mode)
    set(test_arg)
    if (ARGN)
        set(test_arg "-DTEST_PATH=${ARGN}")
    endif ()
    #a quoted argument with ; is one argument: the list arrives as a list
    execute_process(
        COMMAND ${CMAKE_COMMAND} "-DPREFIX=${prefix}" "-DTEST_HOME_DIR=${WORK}/test-home"
            "-DBINDIR=${BINDIR}" "-DLIBDIR=${LIBDIR}" "-DCORE_DIR=${CORE_DIR}"
            "-DTOOLKITS=${toolkits}" "-DMODE=${mode}" ${test_arg} -P "${script}"
        RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " text "${out} ${err}")
    set(run_rc ${rc} PARENT_SCOPE)
    set(run_out "${text}" PARENT_SCOPE)
endfunction()

function(expect name success text)
    #only the end of a long output (a full self-test run) in a failure
    string(LENGTH "${run_out}" len)
    if (len GREATER 3000)
        math(EXPR start "${len} - 3000")
        string(SUBSTRING "${run_out}" ${start} -1 run_out)
    endif ()
    if (success AND NOT run_rc EQUAL 0)
        message(FATAL_ERROR "runner_checks: case ${name}: failed (${run_rc})\n${run_out}")
    endif ()
    if (NOT success AND run_rc EQUAL 0)
        message(FATAL_ERROR "runner_checks: case ${name}: did not fail\n${run_out}")
    endif ()
    if (text)
        string(FIND "${run_out}" "${text}" pos)
        if (pos EQUAL -1)
            message(FATAL_ERROR "runner_checks: case ${name}: the output does not contain \"${text}\"\n${run_out}")
        endif ()
    endif ()
    message(STATUS "runner_checks: ${name} OK")
endfunction()

#a copy of the stage for the cases that change it
function(copy_stage dest)
    file(REMOVE_RECURSE "${dest}")
    file(COPY "${STAGE}/" DESTINATION "${dest}")
endfunction()

#good
run_script("${STAGE}" "${TOOLKITS}" modules)
expect(good_modules TRUE "")
run_script("${STAGE}" "${TOOLKITS}" selftests)
expect(good_selftests TRUE "tests passed")

#broken_module
list(GET TOOLKITS 0 first_toolkit)
copy_stage("${WORK}/stage-broken")
file(GLOB toolkit_dirs "${WORK}/stage-broken/${LIBDIR}/Pothos/modules*/${first_toolkit}")
list(GET toolkit_dirs 0 toolkit_dir)
#the module suffix of the core (MODULE_EXT): .so also on macOS
if (WIN32)
    set(module_suffix .dll)
else ()
    set(module_suffix .so)
endif ()
file(WRITE "${toolkit_dir}/libBroken${module_suffix}" "not a module")
run_script("${WORK}/stage-broken" "${TOOLKITS}" modules)
expect(broken_module FALSE "libBroken")

#foreign_plugin_path: a dir with a copy of one module of the stage
file(GLOB stage_modules "${STAGE}/${LIBDIR}/Pothos/modules*/${first_toolkit}/*${module_suffix}")
list(GET stage_modules 0 one_module)
file(REMOVE_RECURSE "${WORK}/foreign-plugins")
file(COPY "${one_module}" DESTINATION "${WORK}/foreign-plugins")
set(ENV{POTHOS_PLUGIN_PATH} "${WORK}/foreign-plugins")
run_script("${STAGE}" "${TOOLKITS}" selftests "${QUICK_TEST}")
unset(ENV{POTHOS_PLUGIN_PATH})
expect(foreign_plugin_path TRUE "")

#foreign_module: the path check with a fake --list-modules output
set(check "${WORK}/check_paths.cmake")
foreach(variant inside outside)
    set(lines "${STAGE}/${LIBDIR}/Pothos/modules/a/libA.so   (3 plugins) [1.0]\n")
    if (variant STREQUAL "outside")
        string(APPEND lines "/elsewhere/lib/Pothos/modules/b/libB.so   (1 plugins) [1.0]\n")
    endif ()
    file(WRITE "${check}"
        "include(\"${CMAKE_CURRENT_LIST_DIR}/../cmake/PothosBaseModulePaths.cmake\")\n"
        "pothos_base_check_module_paths(\"${lines}\" \"${STAGE}\")\n")
    execute_process(COMMAND ${CMAKE_COMMAND} -P "${check}"
        RESULT_VARIABLE run_rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " run_out "${out} ${err}")
    if (variant STREQUAL "inside")
        expect(foreign_module_inside TRUE "")
    else ()
        expect(foreign_module_outside FALSE "/elsewhere/lib/Pothos/modules/b/libB.so")
    endif ()
endforeach()

#no_toolkit_tests
run_script("${STAGE}" "${TOOLKITS};nosuch" selftests)
expect(no_toolkit_tests FALSE "no self-tests under /nosuch/tests")

#relative_prefix: the same stage as a relative path from its parent dir
cmake_path(GET STAGE PARENT_PATH stage_parent)
cmake_path(GET STAGE FILENAME stage_name)
set(test_arg "-DTEST_PATH=${QUICK_TEST}")
execute_process(
    COMMAND ${CMAKE_COMMAND} "-DPREFIX=${stage_name}" "-DTEST_HOME_DIR=${WORK}/test-home"
        "-DBINDIR=${BINDIR}" "-DLIBDIR=${LIBDIR}" "-DCORE_DIR=${CORE_DIR}"
        "-DTOOLKITS=${TOOLKITS}" -DMODE=selftests "${test_arg}" -P "${script}"
    WORKING_DIRECTORY "${stage_parent}"
    RESULT_VARIABLE run_rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
string(REGEX REPLACE "[ \t\r\n]+" " " run_out "${out} ${err}")
expect(relative_prefix TRUE "success!")

#stage_clean: an old stage prefix with a module that the build does not have
if (BUILD_DIR)
    set(stage_script "${CMAKE_CURRENT_LIST_DIR}/../cmake/PothosBaseStage.cmake")
    set(clean_prefix "${WORK}/stage-clean")
    file(REMOVE_RECURSE "${clean_prefix}")
    file(WRITE "${clean_prefix}/${LIBDIR}/Pothos/modules0.0-0/old/libOld${module_suffix}" "old")
    file(WRITE "${clean_prefix}/.pothos-base-stage" "")
    execute_process(
        COMMAND ${CMAKE_COMMAND} "-DBUILD_DIR=${BUILD_DIR}" "-DPREFIX=${clean_prefix}" -P "${stage_script}"
        RESULT_VARIABLE run_rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " run_out "${out} ${err}")
    expect(stage_clean_install TRUE "")
    if (EXISTS "${clean_prefix}/${LIBDIR}/Pothos/modules0.0-0" OR NOT EXISTS "${clean_prefix}/${BINDIR}")
        message(FATAL_ERROR "runner_checks: case stage_clean: the old module stays, or the install is missing")
    endif ()
    message(STATUS "runner_checks: stage_clean_removed OK")

    #a dir without the marker, outside the build dir, is not removed. The
    #script may remove any dir in its BUILD_DIR, and WORK can be in the real
    #build dir (CI): thus this case gives a build dir of its own
    set(foreign_prefix "${WORK}/not-a-stage")
    file(REMOVE_RECURSE "${foreign_prefix}")
    file(WRITE "${foreign_prefix}/keep.txt" "keep")
    execute_process(
        COMMAND ${CMAKE_COMMAND} "-DBUILD_DIR=${WORK}/other-build" "-DPREFIX=${foreign_prefix}" -P "${stage_script}"
        RESULT_VARIABLE run_rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    string(REGEX REPLACE "[ \t\r\n]+" " " run_out "${out} ${err}")
    expect(stage_clean_refuses FALSE "not a stage prefix")
    if (NOT EXISTS "${foreign_prefix}/keep.txt")
        message(FATAL_ERROR "runner_checks: case stage_clean_refuses: the dir was removed")
    endif ()
else ()
    message(STATUS "runner_checks: stage_clean skipped (no BUILD_DIR)")
endif ()

#env: a developer shell (the user dirs of the check, not the real home)
if (ENV_SCRIPT AND NOT WIN32)
    set(ENV{XDG_DATA_HOME} "${WORK}/env-home/data")
    set(ENV{XDG_CONFIG_HOME} "${WORK}/env-home/config")
    set(ENV{POTHOS_PLUGIN_PATH} "${WORK}/foreign-plugins")
    execute_process(
        COMMAND bash -c "source '${ENV_SCRIPT}' && echo \"PLUGIN_PATH=[$POTHOS_PLUGIN_PATH]\" && PothosUtil --self-test1 '${QUICK_TEST}'"
        RESULT_VARIABLE run_rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
    unset(ENV{POTHOS_PLUGIN_PATH})
    string(REGEX REPLACE "[ \t\r\n]+" " " run_out "${out} ${err}")
    expect(env_plugin_path TRUE "PLUGIN_PATH=[]")
    expect(env_self_test TRUE "success!")
else ()
    message(STATUS "runner_checks: env skipped (no ENV_SCRIPT, or Windows)")
endif ()

message(STATUS "runner_checks: all cases passed")
