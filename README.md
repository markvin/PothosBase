# PothosBase

PothosBase is the aggregate build of the Pothos core and its toolkits.
The core and each toolkit are git submodules on their `pothos2` branches.
One CMake tree builds them with `add_subdirectory`. One `ctest` installs
everything into one stage prefix and runs all self-tests from it.

Use PothosBase for development: a change of the core is checked against
the real toolkits, and a debugger steps from a block into the core. A
user of a toolkit builds it against an installed core, as the README of
the toolkit tells. PothosBase does not replace that build.

| Directory | Repository | Branch |
|---|---|---|
| `core/` | https://github.com/markvin/PothosCore | `pothos2` |
| `blocks/` | https://github.com/markvin/PothosBlocks | `pothos2` |
| `comms/` | https://github.com/markvin/PothosComms | `pothos2` |
| `widgets/` | https://github.com/markvin/PothosWidgets | `pothos2` |
| `soapy/` | https://github.com/markvin/PothosSoapy | `pothos2` |
| `plotters/` | https://github.com/markvin/PothosPlotters | `pothos2` |
| `flow/` | https://github.com/markvin/PothosFlow | `pothos2` |
| `audio/` | https://github.com/markvin/PothosAudio | `pothos2` |

The submodule commits in `main` are a set that builds and passes the
tests. CI checks this for each change.

## Clone

```sh
git clone --recurse-submodules https://github.com/markvin/PothosBase.git
```

If you cloned without `--recurse-submodules`, run
`git submodule update --init`. Configure stops with this command when a
submodule is missing.

## Dependencies

The dependencies of all repositories (nlohmann_json, Asio, xsimd, Qt 6
for widgets, plotters and flow, SoapySDR for soapy, Qwt for plotters) come from
`find_package`. audio has a copy of miniaudio and needs no audio packages. Use one of
these two methods:

- System packages. Arch: `pacman -S asio nlohmann-json xsimd qt6-base soapysdr qwt`.
- Conan 2:

  ```sh
  conan install . --output-folder=build/conan -s build_type=Debug -s compiler.cppstd=23 --build=missing
  ```

  Then give `-DCMAKE_TOOLCHAIN_FILE=build/conan/conan_toolchain.cmake`
  to CMake. `conanfile.txt` contains the same versions as the
  `conanfile.txt` of each submodule.

Qt 6 (6.5 or higher) is not a Conan package. Install it from the system
packages or with the Qt installer. When Qt is not in a default location of
the system, add its prefix to `CMAKE_PREFIX_PATH`. When Qt 6 is missing,
configure stops with an error; `-DPOTHOS_BASE_WITH_WIDGETS=OFF`,
`-DPOTHOS_BASE_WITH_PLOTTERS=OFF` and `-DPOTHOS_BASE_WITH_FLOW=OFF` build
without widgets, plotters and flow.

SoapySDR (0.8 or higher) is not a Conan package. Install it from the
system packages, or build it from the source
(https://github.com/pothosware/SoapySDR) and add its install prefix to
`CMAKE_PREFIX_PATH`. When SoapySDR is missing, configure stops with an
error; `-DPOTHOS_BASE_WITH_SOAPY=OFF` builds without soapy.

Qwt (6.3 or higher, built for Qt 6) is not a Conan package. Install it
from the system packages, or build it from the source
(https://qwt.sourceforge.io) with the `qmake` of your Qt 6 and add its
install prefix to `CMAKE_PREFIX_PATH`. When Qwt is missing, or it is built
for Qt 5, configure stops with an error; `-DPOTHOS_BASE_WITH_PLOTTERS=OFF`
builds without plotters.

## Build

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

Options:

- `POTHOS_BASE_WITH_<TOOLKIT>` (default ON): build the toolkit, for
  example `POTHOS_BASE_WITH_BLOCKS`. The comms, soapy, plotters, flow and
  audio tests need blocks: with the tests on, one of them without blocks is a
  configure error. Plotters needs comms (the plotters use
  `/comms/wave_trigger`): plotters without comms is a configure error.
  Widgets needs Qt 6. Soapy needs SoapySDR. Plotters needs Qt 6 and Qwt.
  Flow needs Qt 6.
- `POTHOS_BASE_<NAME>_DIR`: the source directory of a repository
  (default: its submodule). Refer to "Local clones".
- `POTHOS_BASE_WARNINGS_AS_ERRORS` (default OFF): treat compiler warnings
  as errors in all repositories (GCC and Clang).
- `POTHOS_BASE_BUILD_TESTS` (default ON at the top level).

`build/compile_commands.json` contains the sources of all repositories
(clangd finds it there).

## Test

```sh
ctest --test-dir build --output-on-failure
```

The tests:

1. `base.stage` installs the whole tree into `build/stage`.
2. `base.modules` loads each module of the stage prefix. A module that
   does not load fails this test.
3. `base.selftests` runs all self-tests of the core and the toolkits from
   the stage prefix. All modules must come from the stage prefix
   (`POTHOS_PLUGIN_PATH` is not used). Each toolkit must give at least one
   self-test (flow is an application without self-tests: it has
   `base.flow`). The widgets and plotters tests need no display: CTest sets
   `QT_QPA_PLATFORM=offscreen`. The soapy tests need no SDR hardware:
   they use a SoapySDR test driver of soapy. The audio tests need no
   sound card: the test runner sets `POTHOS_AUDIO_BACKEND=null` (the null
   backend of miniaudio) when it is not set.
4. `base.flow` runs the smoke test of flow (`PothosFlowSmokeTest`) from
   the stage prefix: the main window, the block cache, Help → About, the
   message window and the exit, with the Qt platform `offscreen`. The
   main window starts a Pothos server on the fixed locator port, thus the
   test has the CTest resource lock `pothos_locator_port`.

To run one self-test, run this command after `base.stage`:

```sh
cmake -DPREFIX=build/stage -DTEST_HOME_DIR=build/test-home -DBINDIR=bin -DLIBDIR=lib \
  -DCORE_DIR=core -DTOOLKITS=blocks -DMODE=selftests \
  -DTEST_PATH=/blocks/tests/test_copier_domain_crossing -P cmake/PothosBaseSelfTests.cmake
```

The checks of PothosBase itself are `cmake -P` scripts in `tests/`
(`configure_checks.cmake`, `runner_checks.cmake`). Each script tells its
arguments in its first comment.

## Debug

1. Build with `CMAKE_BUILD_TYPE=Debug`.
2. Run `ctest --test-dir build -R base.stage` to fill the stage prefix.
3. In a bash or zsh shell, run `source build/pothos-env.sh`. In
   PowerShell, run `. build/pothos-env.ps1`.
4. Run `PothosUtil` of the stage prefix under the debugger:

   ```sh
   gdb --args PothosUtil --self-test1 /blocks/tests/test_copier_domain_crossing
   ```

The environment file sets `POTHOS_ROOT` to the stage prefix, adds its
`bin` to `PATH` and its library dir to the library path, and unsets
`POTHOS_PLUGIN_PATH`. It does not change your user data dirs.

## Local clones

You can build your own clones in place of the submodules. Then you edit
in the usual clones and check them together.

1. Configure with the `_DIR` option of each clone that you change:

   ```sh
   cmake -S . -B build -DPOTHOS_BASE_CORE_DIR=$HOME/Projects/PothosCore \
     -DPOTHOS_BASE_BLOCKS_DIR=$HOME/Projects/PothosBlocks
   ```

2. Edit, build and test in this build directory.
3. Merge the changes in the repositories of the clones.
4. Move the submodule pointers (refer to the next section).

Configure prints the path and `git describe` of each clone, and one
warning: this build is not the fixed set of the submodule pointers. Only a
build without `_DIR` options proves that set. To go back to a submodule,
remove the option: `cmake -B build -UPOTHOS_BASE_CORE_DIR`.

## Update of the submodule pointers

1. Merge the change into the `pothos2` branch of the submodule
   repository.
2. In PothosBase, run `git submodule update --remote <name>`.
3. Build and run the tests locally, or open a PR and let CI do it.
4. Merge the PR into `main`.

A change that needs the core and a toolkit together uses this order:
merge the core change, then the toolkit change, then one PothosBase PR
that moves both pointers.

## Add a toolkit

Add a toolkit after its port to the pothos2 core:

1. Run `git submodule add -b pothos2 <URL> <name>`.
2. Add its name to `pothos_base_all_toolkits` in `CMakeLists.txt`, after
   the toolkits that its tests need.
3. Add its `warnings as errors` option to the forward list in
   `CMakeLists.txt`.
4. Add its name to `-DTOOLKITS=` of the "Runner checks" step in
   `.github/workflows/ci.yml` (not for an application without self-tests,
   for example flow).
5. Add its Conan requirements to `conanfile.txt` (the same versions).
6. Run the build, `ctest` and `tests/configure_checks.cmake`.

## License

The repositories in the submodules have their own licenses. The files of
PothosBase have the Boost Software License 1.0, the same as Pothos.
