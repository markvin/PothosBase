########################################################################
# Check conanfile.txt of PothosBase against the submodules (cmake -P).
#
# Required: -DSRC=<PothosBase source>
#
# The [requires] of PothosBase must be the union of the [requires] of the
# submodules, with the same version of each package. A package with two
# versions, or a package of a submodule that PothosBase does not have,
# stops with an error.
########################################################################
cmake_minimum_required(VERSION 3.25)
if (NOT DEFINED SRC)
    message(FATAL_ERROR "check_conan_versions: SRC is not set")
endif ()

#read_requires(<conanfile.txt> <out var>): a list of name/version
function(read_requires file out)
    file(STRINGS "${file}" lines)
    set(in_requires FALSE)
    set(result)
    foreach(line IN LISTS lines)
        string(STRIP "${line}" line)
        if (line MATCHES "^\\[(.*)\\]$")
            if (CMAKE_MATCH_1 STREQUAL "requires")
                set(in_requires TRUE)
            else ()
                set(in_requires FALSE)
            endif ()
        elseif (in_requires AND line MATCHES "^([^/# ]+)/([^@# ]+)")
            list(APPEND result "${CMAKE_MATCH_1}/${CMAKE_MATCH_2}")
        endif ()
    endforeach()
    set(${out} ${result} PARENT_SCOPE)
endfunction()

read_requires("${SRC}/conanfile.txt" base_requires)

#the submodule paths from .gitmodules
file(STRINGS "${SRC}/.gitmodules" path_lines REGEX "^[ \t]*path[ \t]*=")
set(errors)
foreach(path_line IN LISTS path_lines)
    string(REGEX REPLACE "^[ \t]*path[ \t]*=[ \t]*" "" sub "${path_line}")
    if (NOT EXISTS "${SRC}/${sub}/conanfile.txt")
        continue()
    endif ()
    read_requires("${SRC}/${sub}/conanfile.txt" sub_requires)
    foreach(req IN LISTS sub_requires)
        string(REGEX REPLACE "/.*" "" name "${req}")
        set(found "")
        foreach(base_req IN LISTS base_requires)
            if (base_req MATCHES "^${name}/")
                set(found "${base_req}")
            endif ()
        endforeach()
        if (NOT found)
            list(APPEND errors "${sub} needs ${req}, conanfile.txt of PothosBase does not have ${name}")
        elseif (NOT found STREQUAL req)
            list(APPEND errors "${name}: ${sub} needs ${req}, PothosBase has ${found}")
        endif ()
    endforeach()
endforeach()

if (errors)
    list(JOIN errors "\n  " text)
    message(FATAL_ERROR "check_conan_versions:\n  ${text}")
endif ()
message(STATUS "check_conan_versions: OK (${base_requires})")
