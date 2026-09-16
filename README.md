# MOSIT — Multi Operational System Install Toolkit

**MOSIT** is a family of interactive BASH installers that build numerical
weather/climate prediction software from source on 64-bit Linux (and macOS for
WRF), handling every dependency automatically: compilers, MPI, I/O libraries,
the model cores, pre/post-processing tools, and optional data-assimilation
components.

This repository ships two installers:

| Script          | Installs |
| --------------- | -------- |
| `WRF-MOSIT.sh`  | Weather Research & Forecasting family: WRF-ARW, WRF-Chem, WRF-Hydro (standalone & coupled), WRF-CMAQ, WRF-SFIRE, COAWST |
| `MPAS-MOSIT.sh` | Model for Prediction Across Scales family: MPAS-Atmosphere, MPAS-Ocean, MPAS-Seaice, MPAS-Albany Land Ice — plus MPAS-Limited-Area, MPAS-Tools/geometric_features/pyremap, static datasets, and **MPAS-JEDI** (experimental) |

> The full original WRF-MOSIT documentation (including its complete reference
> list) is preserved in [`docs/README-WRF-MOSIT-legacy.md`](docs/README-WRF-MOSIT-legacy.md).

---

## Quick start

```bash
cd $HOME
sudo apt install git -y           # or: sudo dnf install git -y
git clone https://github.com/HathewayWill/WRF-MOSIT.git
cd WRF-MOSIT
chmod +x *.sh

./WRF-MOSIT.sh   2>&1 | tee WRF_MOSIT.log     # WRF family
./MPAS-MOSIT.sh  2>&1 | tee MPAS_MOSIT.log    # MPAS family
```

Both scripts are interactive: they detect your OS/architecture, ask what to
install, then compile everything unattended. **Re-running is safe** — finished
steps are detected and skipped (see *Idempotent re-runs*).

---

# Part I — WRF-MOSIT (summary)

Mature bash installer for the WRF ecosystem on:

- Linux Debian family (Ubuntu, Mint, Pop!_OS, …) — GNU and Intel
- Linux Fedora family (CentOS, Rocky, RHEL, Alma) — GNU and Intel
- macOS (Homebrew) — GNU only
- Windows Subsystem for Linux (Debian/Ubuntu/Mint)

### Models (one per run)

| Model | Notes |
| ----- | ----- |
| WRF-ARW v4.8.0 | core atmosphere model + WPS v4.7.0, basic nesting set up |
| WRF-Chem v4.8.0 | chemistry w/ KPP + WPS + Prep-Chem-SRC (GNU) |
| WRF-Hydro Standalone v5.4 | hydrology model |
| WRF-Hydro Coupled v5.4 | WRF v4.8.0 coupled with WRF-Hydro |
| WRF-CMAQ (CMAQ v5.5) | WRF v4.5.0 + CMAQ + WPS |
| WRF-SFIRE v2 | wildland fire (WPS v4.2) |
| COAWST | coupled ocean-atmosphere-wave-sediment transport |

Compiler support: GNU on all platforms; Intel on Linux x86_64 (CMAQ/SFIRE are
GNU only).

### Libraries / pre-post tools

zlib 1.3.2 · MPICH 5.0.1 · libpng 1.6.58 · JasPer 1900.1 · HDF5/PHDF5 1.14.6 ·
Parallel-NetCDF 1.14.1 · NetCDF-C 4.10.0 · NetCDF-Fortran 4.6.2 · NetCDF-CXX
4.3.1 · MET 12.2.1 / METplus 6.2.1 · WRF-Python, NCL, CDO (conda) ·
GrADS/OpenGrADS · WRF-GIS-Preprocessor (Hydro).

Conda envs created: `cdo_stable`, `ncl_stable`, `wrf-python`, `wrfh_gis_env`
(under `$HOME/<WRF folder>/miniconda3`).

### Requirements

~350 GB free disk, ≥16 GB RAM, ≥8 cores. Estimated runtime **60–120 min** at
10 Mbps (Intel slower). Install folder: `$HOME/<WRF|WRF_CHEM|WRFHYDRO|
WRF_COUPLED|WRF_SFIRE|WRF_CMAQ|COAWST>` (plus `_Intel` suffix for Intel).

WRF runtime exports (GNU):

```bash
export LD_LIBRARY_PATH=$HOME/WRF/Libs/NETCDF/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$HOME/WRF/Libs/grib2/lib:$LD_LIBRARY_PATH
export PATH=$HOME/WRF/Libs/MPICH/bin:$PATH
export PATH=$HOME/WRF/GrADS/Contents:$PATH
```

Intel additionally: `source /opt/intel/oneapi/setvars.sh`.

---

# Part II — MPAS-MOSIT (new)

Interactive installer for the **Model for Prediction Across Scales (MPAS)**
(<https://github.com/MPAS-Dev/MPAS-Model>), same MOSIT design:
source-compiled dependencies, per-component menus, isolated install folder,
managed `~/.bashrc` block.

## 1. Core dependencies (compiled from source)

Installed under `~/MPAS_GNU/Libs/` (`~/MPAS_Intel/Libs/` for Intel), built in
this order:

| Library | Version | Notes |
| ------- | ------- | ----- |
| zlib | 1.3.2 | compression |
| MPICH | 5.0.1 | MPI; `mpicc`/`mpifort` in `Libs/MPICH` |
| HDF5 | 1.14.6 | parallel + Fortran, built with MPI wrappers |
| Parallel-NetCDF | 1.14.1 | **required by every MPAS core** |
| NetCDF-C | 4.10.0 | pnetcdf/cdf5/parallel/NETCDF4 enabled |
| NetCDF-Fortran | 4.6.2 | same prefix (`Libs/NETCDF`) |
| METIS | 5.1.0 | provides `gpmetis` (mesh partitioning) |

After the libraries, two runtime compatibility tests are compiled and executed:
a parallel `pnetcdf_test` (via `mpirun -np 1`) and a `netcdf_fortran_test`.
Failures prompt before continuing.

## 2. MPAS-Model v8.4.2 — core selection menu

| Menu | Builds | Executable(s) |
| ---- | ------ | ------------- |
| 1 MPAS-Atmosphere | atmosphere + preprocessor | `atmosphere_model`, `init_atmosphere_model` |
| 2 MPAS-Ocean      | ocean (fetches CVMix + BGC during build) | `ocean_model` |
| 3 MPAS-Seaice     | sea ice | `seaice_model` |
| 4 MPAS-Albany Land Ice | land ice | `landice_model` |
| 5 MPAS-ALL        | everything above | all |
| 6 MPAS-JEDI only  | all cores + JEDI | all + JEDI |

Build actually executed:
`make -j<N> gnu CORE=<core> PRECISION=<single|double>` (Intel = `intel` target,
**experimental**, needs oneAPI `icx`/`ifx`).

- **PRECISION**: `single` recommended for Atmosphere; `double` is **required**
  for MPAS-JEDI (the script prompts for it).
- On failure a core is retried with `AUTOCLEAN=true`, then rebuilt once more.
- Each executable is copied to `~/MPAS_GNU/bin/` along with the physics tables
  (`*TBL`, `*DATA*`, `.DBL` variants for double precision) and the generated
  default `namelist.*`/`streams.*`.

## 3. Optional components (Yes/No prompts)

| Component | What you get | Location |
| --------- | ------------ | -------- |
| Metis (`gpmetis`) | runtime partitioner for parallel runs | `~/MPAS_GNU/Libs/METIS/bin` |
| MPAS-Limited-Area | `create_region`, `create_initial_state` for regional runs | `~/MPAS_GNU/tools/MPAS-Limited-Area` (on PATH) |
| Python tooling | `mpas_tools`, `geometric_features`, `pyremap` | conda env **`mpas`** (conda-forge) when conda/mamba exists, otherwise repo clones + venv in `tools/venv-mpas` |
| Static datasets | MPAS-Data clone + `mpas_static.tar.bz2` (~2.2 GB static fields) + `QNWFA_QNIFA_SIGMA_MONTHLY.dat` (~215 MB aerosols) | `~/MPAS_GNU/data/` |
| MPAS-JEDI | data-assimilation stack (below) | `~/MPAS_GNU/jedi/` |

## 4. MPAS-JEDI (EXPERIMENTAL)

Installed through the JCSDA [mpas-bundle](https://github.com/JCSDA/mpas-bundle)
ecbuild superbuild inside a dedicated conda env **`jedi`** (python, cmake/ninja,
eckit, fckit, ecbuild, atlas, oops, vader, saber, ioda, ufo, crtm from
conda-forge). If no conda is found, **Miniforge** is installed silently into
`~/MPAS_GNU/tools/miniforge3`.

- Requires MPAS built in **double precision** (`-DMPAS_DOUBLE_PRECISION=ON`);
  `git-lfs` is installed if missing.
- The bundle clones `MPAS-Model` (develop) into the build tree itself.
- JEDI failures are **warnings only** — the model install still completes.
  Expect long builds; afterwards run
  `ctest --output-on-failure` in `~/MPAS_GNU/jedi/mpas-bundle-build`.

## Folder layout

```
~/MPAS_GNU/                    (or ~/MPAS_Intel/)
├── Downloads/                 source tarballs (kept for re-runs)
├── Libs/
│   ├── base/                  zlib + HDF5 + PnetCDF     ($PNETCDF, $HDF5)
│   ├── NETCDF/                NetCDF-C + NetCDF-Fortran ($NETCDF)
│   ├── MPICH/                 MPI compilers + mpirun
│   └── METIS/                 gpmetis and friends
├── bin/                       <core>_model executables + physics tables (on PATH)
├── Logs/                      per-step build logs (check these first)
├── tests/compat/              PnetCDF / NetCDF-Fortran compatibility tests
├── data/                      MPAS-Data, mpas_static/, QNWFA file
├── tools/                     MPAS-Limited-Area, MPAS-Tools, geometric_features,
│                              pyremap, venv-mpas, miniforge3 (if JEDI)
└── jedi/                      mpas-bundle src + mpas-bundle-build
```

## Environment (`~/.bashrc` managed block)

Between `# BEGIN/END MPAS-MOSIT v1.0.0 exports` the script maintains:

```bash
export MPAS_FOLDER="$HOME/MPAS_GNU"
export NETCDF="$MPAS_FOLDER/Libs/NETCDF"
export PNETCDF="$MPAS_FOLDER/Libs/base"
export HDF5="$MPAS_FOLDER/Libs/base"
export MPAS_EXE_DIR="$MPAS_FOLDER/bin"
export PATH="$MPAS_FOLDER/bin:$MPAS_FOLDER/Libs/MPICH/bin:$PATH"
export PATH="$MPAS_FOLDER/Libs/METIS/bin:$PATH"          # if Metis selected
export LD_LIBRARY_PATH="$MPAS_FOLDER/Libs/base/lib:$NETCDF/lib:$MPAS_FOLDER/Libs/MPICH/lib:..."
export MPAS_LIMITED_AREA_DIR=...   # optional
export MPAS_STATIC_DATA_DIR="$MPAS_FOLDER/data"   # optional
export MPAS_JEDI_DIR="$MPAS_FOLDER/jedi"          # optional
```

Open a **new terminal** (or `source ~/.bashrc`) after each run.

## Running MPAS

1. **Partition the mesh** for N MPI tasks (runtime step):

   ```bash
   gpmetis -minconn -contig -niter=200 <case>.graph.info 16   # -> <case>.graph.info.16
   ```

   `*.graph.info` files ship with MPAS-Model example/test cases.

2. **Execute** from a run directory containing the exe, the case `.nc` files and
   `namelist.*`/`streams.*`:

   ```bash
   mpirun -np 16 atmosphere_model    # or ocean_model / seaice_model / landice_model
   ```

3. **Atmosphere workflow**: `init_atmosphere_model` first (converts the
   initial-condition file), then `atmosphere_model`. Real cases need the static
   fields from `~/MPAS_GNU/data` and the aerosol climatology file.

4. **Limited area**: `create_region region.pts global_grid.nc` (polygon must be
   convex for `grid.nc` subsets) → `create_initial_state ...`; see the
   MPAS-Limited-Area README.

5. **Python tools**: `conda activate mpas` (or source `tools/venv-mpas`) to use
   `mpas_tools`, `geometric_features`, `pyremap` (`pyremap` full remapping needs
   `esmpy`, best from conda-forge).

## Idempotent re-runs

Every expensive step records a marker and is skipped later:

| Step | Skipped when |
| ---- | ------------ |
| Dependency library | installed marker exists (`Libs/base/include/pnetcdf.h`, `Libs/NETCDF/lib/libnetcdf.so`, `Libs/MPICH/bin/mpicc`, …) |
| METIS | `Libs/METIS/bin/gpmetis` exists |
| MPAS core | `bin/<exe>` exists — force with `MPAS_FORCE_REBUILD=1 ./MPAS-MOSIT.sh` |
| MPAS-Model clone / static data / tools | already cloned/downloaded |
| conda envs `mpas`, `jedi` | listed by `conda env list` |
| `~/.bashrc` block | replaced in place, never duplicated |

So recovering from any failure = fix the cause and run the script again.

## Troubleshooting & verified quirks

- **CMake ≥ 4 vs METIS 5.1.0**: upstream METIS uses
  `cmake_minimum_required(VERSION 2.8)` and a relative `try_compile` path that
  CMake 4 rejects. The script patches `CMakeLists.txt` and configures with
  `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` and an **absolute** `-DGKLIB_PATH` —
  do the same for manual builds.
- **Official METIS mirrors are dead** (glaros/INRIA etc.); the Metis sources
  come from the Debian orig mirror (`deb.debian.org/.../metis_5.1.0.dfsg.orig.tar.xz`).
- **`conda create` → `MultipleKeysError`**: remove duplicate `auto_activate_base:`
  / `auto_activate:` from `~/.condarc` (keep one).
- **Intel compiler path is experimental** (oneAPI `icx`/`icpx`/`ifx`); GNU is
  the tested route.
- Logs to check: `~/MPAS_GNU/Logs/<lib>/{configure,make,make.install}.log`,
  `~/MPAS_GNU/Logs/build_core_<core>.log`,
  `~/MPAS_GNU/Logs/{METIS_build,pnetcdf_test,netcdf_fortran_test}.log`,
  `~/MPAS_GNU/Logs/{conda_env_mpas,conda_env_jedi,jedi_cmake,jedi_make}.log`.
- The **ocean** core is slower: it downloads CVMix/BGC sources at first build.
- The script deactivates any active conda env at start to keep the model build
  clean, and clears the sudo password from the environment after installs.

## System requirements & timing (MPAS-MOSIT)

- 64-bit Linux (x86_64/aarch64; Debian/Ubuntu & Fedora/RHEL families), ≥ 50 GB
  free disk, ≥ 16 GB RAM, ≥ 4 cores (uses half of `nproc` for `make -j`).
- Approximate wall time on an 8-core laptop: dependencies 25–45 min ·
  each core 10–30 min (ocean longest) · static datasets ≈ 2.4 GB download ·
  JEDI + mpas-bundle +30–90 min (flakiest part, never blocks the install).
- Verified on: Pop!_OS 22.04 (Ubuntu 22.04 base), x86_64, GNU 11.4, CMake 4.4,
  8 cores / 16 GB RAM — atmosphere (double precision) ✓, pnetcdf &
  netcdf-fortran compat tests ✓, gpmetis ✓, `gpmetics`/conda env flows ✓.

## References

- MPAS: <https://mpas-dev.github.io> · Ringler et al. (2020) *Computer Physics
  Communications* (MPAS core) and the core-specific papers (atmosphere:
  Skamarock et al. 2012 *MWR*; ocean: Petersen et al. 2020 *Ocean Modelling*;
  land ice: Price et al. 2019 *GMD*; sea ice: Liu et al. 2018 *JAMES*).
- MPAS-JEDI / JEDI: <https://jcda.org> · JCSDA (2020) *QJRMS* JEDI OSS.
- MPAS-Limited-Area: <https://github.com/MPAS-Dev/MPAS-Limited-Area>.
- METIS: Karypis, G. (2013) METIS 5.1.0, University of Minnesota.

### Citation

Hatheway, W., Snoun, H., ur Rehman, H., & Mwanthi, A. W. (2023). WRF-MOSIT: a
modular and cross-platform tool for configuring and installing the WRF model.
*Earth Science Informatics*. <https://doi.org/10.1007/s12145-023-01136-y>

MPAS-MOSIT reuses that toolkit design; when publishing, also cite the MPAS
project and, if used, JCSDA/JEDI.

### Special thanks (preserved from the WRF-MOSIT project)

University of Zadar's Ivan T. (meteoadriatic) · GitHub user jamal919 ·
University of Manchester's Doug L. · Institute of Water & Flood Management
(BUET)'s Yeamin R., Saiful Islam F. · University of Tunis El Manar's Hosni S. ·
GSL's Jordan S. · NCAR's Mary B., Christine W., Soren R., Carl D. · DTC's
Tara J., Julie P., George M., John H. · UCAR's Katelyn F., Jim B., Jordan P.,
Kevin M.
