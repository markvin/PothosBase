#!/usr/bin/env bash
########################################################################
# Check that each submodule pointer is a commit of the branch that
# .gitmodules gives (pothos2). Run it from the PothosBase source dir.
# A shallow submodule (CI checkout) gets its full history first, because
# a shallow history cannot prove that one commit is an ancestor of another.
########################################################################
set -euo pipefail

status=0
while read -r key path; do
    name=${key#submodule.}
    name=${name%.path}
    branch=$(git config -f .gitmodules --get "submodule.${name}.branch" || true)
    if [ -z "$branch" ]; then
        echo "check_submodule_pointers: ${path}: no branch in .gitmodules"
        status=1
        continue
    fi
    if [ "$(git -C "$path" rev-parse --is-shallow-repository)" = "true" ]; then
        git -C "$path" fetch --quiet --unshallow origin "$branch"
    else
        git -C "$path" fetch --quiet origin "$branch"
    fi
    #the pointer in the index (the same as HEAD in CI; a local check can stage a pointer)
    pointer=$(git rev-parse ":${path}")
    if git -C "$path" merge-base --is-ancestor "$pointer" FETCH_HEAD; then
        echo "check_submodule_pointers: ${path} ${pointer:0:12} is on ${branch}"
    else
        echo "check_submodule_pointers: ${path} ${pointer:0:12} is NOT on origin/${branch}"
        status=1
    fi
done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$')
exit $status
