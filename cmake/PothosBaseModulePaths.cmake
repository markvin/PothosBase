########################################################################
# pothos_base_check_module_paths(<list-modules output> <prefix>)
# Stops with an error when a module of the PothosUtil --list-modules output
# is not under <prefix>. A line of the output is:
#   <module path>   (<N> plugins) [<version>]
# The loader searches only the module dir of POTHOS_ROOT, /usr/local when
# the root is /usr, and POTHOS_PLUGIN_PATH (lib/System/Paths.in.cpp of the
# core). This check catches a module from somewhere else, also after a
# change of the loader.
########################################################################
function(pothos_base_check_module_paths output prefix)
    file(TO_CMAKE_PATH "${prefix}" prefix)
    string(REPLACE "\r" "" output "${output}")
    string(REPLACE "\n" ";" lines "${output}")
    foreach(line IN LISTS lines)
        if (NOT line MATCHES "^(.*[^ ]) +\\( *[0-9]+ plugins?\\)")
            continue()
        endif ()
        file(TO_CMAKE_PATH "${CMAKE_MATCH_1}" path)
        string(FIND "${path}" "${prefix}/" pos)
        if (NOT pos EQUAL 0)
            message(FATAL_ERROR "PothosBase: a module loads from outside the stage prefix ${prefix}: ${path}")
        endif ()
    endforeach()
endfunction()
