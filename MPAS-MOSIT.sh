#!/bin/bash
set -o pipefail
ulimit -s unlimited

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Conda environment test (JEDI/tools may use conda, but model build must be clean)
if [ -n "$CONDA_DEFAULT_ENV" ]; then
	echo "CONDA_DEFAULT_ENV is active: $CONDA_DEFAULT_ENV"
	echo "Deactivating it for a clean build environment."
	conda deactivate
	conda deactivate
else
	echo "CONDA_DEFAULT_ENV is not active."
	echo "Continuing script"
fi

start=$(date)
START=$(date +"%s")

############################### Version Numbers ##########################
# For Ease of updating
##########################################################################
export MPAS_VERSION=8.4.2
export MPAS_TAG=v${MPAS_VERSION}

export Zlib_Version=1.3.2
export Mpich_Version=5.0.1
export HDF5_Version=1.14.6
export Pnetcdf_Version=1.14.1
export Netcdf_C_Version=4.10.0
export Netcdf_Fortran_Version=4.6.2
export Metis_Version=5.1.0

############################### Citation Requirement  ####################
echo " "
echo " MPAS-MOSIT (Version 1.0.0) - MPAS Multi Operational System Install Toolkit"
echo " "
echo "Modeled after WRF-MOSIT by W. Hatheway (2023):"
echo "Hatheway, W., Snoun, H., ur Rehman, H., & Mwanthi, A. WRF-MOSIT: a modular"
echo "and cross-platform tool for configuring and installing the WRF model."
echo "Earth Sci Inform (2023). https://doi.org/10.1007/s12145-023-01136-y"
echo " "
echo "Any usage or publication that incorporates or references this software"
echo "must include the citation above, plus standard citation of the MPAS"
echo "project (https://mpas-dev.github.io)."
echo " "
echo -e "\e[31mThis script installs the Model for Prediction Across Scales (MPAS)\e[0m"
echo -e "\e[31mcomponents from https://github.com/MPAS-Dev/MPAS-Model (MPAS v${MPAS_VERSION})\e[0m"
echo " "
read -p "Press enter to continue"

############################### System Architecture Type #################
# Determine if the system is 32 or 64-bit based on the architecture
##########################################################################
export SYS_ARCH=$(uname -m)

if [ "$SYS_ARCH" = "x86_64" ] || [ "$SYS_ARCH" = "aarch64" ]; then
	export SYSTEMBIT="64"
else
	echo "Unsupported architecture: $SYS_ARCH (MPAS-MOSIT supports 64-bit Linux: x86_64 / aarch64)."
	exit 1
fi

[[ "$SYS_ARCH" = "aarch64" ]] && export aarch64=1

############################# System OS Version #############################
#############################################################################
export SYS_OS=$(uname -s)

if [ "$SYS_OS" != "Linux" ]; then
	echo "Unsupported operating system: $SYS_OS (MPAS-MOSIT supports Linux only)."
	exit 1
fi

########## Linux Distribution + Package Manager Detection ##########
if [ -r /etc/os-release ]; then
	. /etc/os-release
	DISTRO_NAME="${NAME:-Linux}"
	DISTRO_VERSION="${VERSION_ID:-unknown}"
	echo "Operating system detected: $DISTRO_NAME, Version: $DISTRO_VERSION"

	case " ${ID:-} ${ID_LIKE:-} " in
	*" rhel "* | *" fedora "* | *" centos "* | *" rocky "* | *" alma linux "*)
		SYSTEMOS="RHL"
		;;
	*" debian "* | *" ubuntu "*)
		SYSTEMOS="Linux"
		;;
	*)
		SYSTEMOS="Linux"
		;;
	esac

	if command -v dnf >/dev/null 2>&1; then
		PKG_MGR="dnf"
	elif command -v apt-get >/dev/null 2>&1; then
		PKG_MGR="apt"
	else
		echo "No supported package manager found (apt or dnf required)."
		exit 1
	fi
else
	echo "/etc/os-release not found. Cannot detect distribution."
	exit 1
fi

echo "Package manager detected: $PKG_MGR"
echo "Final operating system detected: $SYSTEMOS $SYS_ARCH"
echo "Your system is a 64-bit version of Linux Kernel."
echo " "

############################## Compiler Selection #####################
if [ "$SYSTEMOS" = "RHL" ]; then
	ENV_VAR_NAME="RHL_64bit"
else
	ENV_VAR_NAME="Ubuntu_64bit"
fi

if [ -n "${!ENV_VAR_NAME}" ]; then
	echo "The environment variable ${ENV_VAR_NAME} is already set."
else
	echo "The environment variable ${ENV_VAR_NAME} is not set."
fi

echo "Which compiler do you want to use?"
echo "            - GNU                  (recommended, well tested)"
echo "            - Intel                (****EXPERIMENTAL: requires Intel oneAPI****)"
echo " "
while true; do
	read -p "
            Please answer Intel or GNU and press enter (case-sensitive): " yn
	case $yn in
	GNU)
		echo "GNU is selected for installation."
		export COMPILER=GNU
		export COMPILER_TARGET=gnu
		break
		;;
	Intel)
		echo -e "Intel is selected for installation \e[31m(EXPERIMENTAL)\e[0m"
		export COMPILER=Intel
		export COMPILER_TARGET=intel
		break
		;;
	*)
		echo "Please answer Intel or GNU (case-sensitive)."
		;;
	esac
done
echo " "

if [ "$COMPILER" = "Intel" ]; then
	if [ -n "$I_MPI_ONEAPI_ROOT" ] || [ -d /opt/intel/oneapi ]; then
		echo "Intel oneAPI detected."
	else
		echo "Intel oneAPI not found. The oneAPI apt repository will be added."
	fi
fi

############################### Storage check ##########################
echo "--------------------------------------------------"
echo "Testing for storage space for installation."
# Usage: df output in 1K blocks for the home filesystem
AVAIL_KB=$(df -Pk "$HOME" | awk 'NR==2 {print $4}')
AVAIL_GB=$(awk "BEGIN {printf \"%.1f\", $AVAIL_KB/1024/1024}")
MIN_GB=50.0
if awk "BEGIN {exit !($AVAIL_GB < $MIN_GB)}"; then
	echo "Insufficient disk space: ${AVAIL_GB} GiB available (need at least ${MIN_GB} GiB)."
	echo "Exiting."
	exit 1
else
	echo "Disk space check passed: ${AVAIL_GB} GiB available (need at least ${MIN_GB} GiB)."
fi
echo "--------------------------------------------------"

############################### SUDO PASSWORD ###############################
MAX_RETRIES=3
attempt=0
while true; do
	attempt=$((attempt + 1))
	read -r -s -p "
    Password is only saved locally and will not be seen when typing.
    Please enter your sudo password (user account password): " password1
	echo
	read -r -s -p "Please re-enter your password to verify: " password2
	echo
	if [ "$password1" = "$password2" ]; then
		export PASSWD="$password1"
		unset password1 password2
		echo "Password verified successfully."
		break
	else
		echo "Passwords do not match."
		unset password1 password2
	fi
	if ((attempt >= MAX_RETRIES)); then
		echo "Maximum attempts ($MAX_RETRIES) reached. Exiting."
		exit 1
	fi
done
echo "Beginning Installation"
echo ""

##################### Helper functions (MPAS-MOSIT) #####################
log() {
	echo " "
	echo "=================================================="
	echo "$1"
	echo "=================================================="
}

die_on_err() {
	if [ $? -ne 0 ]; then
		echo " "
		echo -e "\e[31mERROR: $1 failed. See logs in ${MPAS_FOLDER}/Logs and the relevant Downloads folder.\e[0m"
		read -r -p "Press 'Enter' to exit script."
		exit 1
	fi
}

run_logged() {
	# usage: run_logged <logfile> <cmd...>
	local logf="$1"
	shift
	echo "$ $*" >>"$logf"
	"$@" >>"$logf" 2>&1
	return $?
}

############################### Core Selection Menu ######################
echo "Which MPAS components would you like to install?"
echo "1) MPAS-Atmosphere   (atmosphere_model + init_atmosphere_model preprocessor)"
echo "2) MPAS-Ocean        (ocean_model)"
echo "3) MPAS-Seaice       (seaice_model)"
echo "4) MPAS-Albany Land Ice (landice_model)"
echo "5) MPAS - All of the above cores"
echo "6) MPAS-JEDI only    (data assimilation, ****EXPERIMENTAL****)"
echo " "
PS3="Please enter the number corresponding to your choice: "
options=("MPAS-Atmosphere" "MPAS-Ocean" "MPAS-Seaice" "MPAS-Albany-LandIce" "MPAS-ALL" "MPAS-JEDI")
select opt in "${options[@]}"; do
	case $opt in
	"MPAS-Atmosphere")
		echo "MPAS-Atmosphere selected for installation"
		export MPAS_PICK_ATM=1
		break
		;;
	"MPAS-Ocean")
		echo "MPAS-Ocean selected for installation"
		export MPAS_PICK_OCEAN=1
		break
		;;
	"MPAS-Seaice")
		echo "MPAS-Seaice selected for installation"
		export MPAS_PICK_SEAICE=1
		break
		;;
	"MPAS-Albany-LandIce")
		echo "MPAS-Albany Land Ice selected for installation"
		export MPAS_PICK_LANDICE=1
		break
		;;
	"MPAS-ALL")
		echo "All MPAS cores selected for installation"
		export MPAS_PICK_ATM=1 MPAS_PICK_OCEAN=1 MPAS_PICK_SEAICE=1 MPAS_PICK_LANDICE=1
		break
		;;
	"MPAS-JEDI")
		echo -e "MPAS-JEDI selected. \e[31mEXPERIMENTAL installation path.\e[0m"
		export MPAS_PICK_ATM=1 MPAS_PICK_OCEAN=1 MPAS_PICK_SEAICE=1 MPAS_PICK_LANDICE=1
		export MPAS_PICK_JEDI=1
		break
		;;
	*)
		echo "Invalid option. Please select a number between 1 and ${#options[@]}."
		;;
	esac
done
echo ""

######################## Secondary configuration prompts ###################
# Precision
echo "Model floating-point precision?"
echo "single is the default and recommended for MPAS-Atmosphere (less memory,"
echo "faster, smaller output). double is required when building MPAS-JEDI."
PS3="Enter your choice (1 or 2): "
options=("single - recommended" "double")
select answer in "${options[@]}"; do
	case $answer in
	"single - recommended")
		export MPAS_PRECISION=single
		echo "single precision selected."
		break
		;;
	"double")
		export MPAS_PRECISION=double
		echo "double precision selected."
		break
		;;
	*)
		echo "Invalid selection. Please try again."
		;;
	esac
done
echo ""

# MPAS-JEDI follow-up (if cores were chosen and JEDI was not already chosen)
if [ -z "$MPAS_PICK_JEDI" ]; then
	echo "NCAR/JCSDA MPAS-JEDI (Model for Prediction Across Scales Joint"
	echo "Effort for Data assimilation Implementation) install"
	echo "Would you like the script to ALSO install MPAS-JEDI via mpas-bundle?"
	echo "This is EXPERIMENTAL: it needs git-lfs, cmake and a conda/mamba"
	echo "environment with JEDI libraries (a Miniforge install is created if"
	echo "conda is not found). Build failures are possible on laptops."
	PS3="Enter your choice (1 for Yes, 2 for No): "
	options=("Yes" "No")
	select answer in "${options[@]}"; do
	case $answer in
	"Yes")
		export MPAS_PICK_JEDI=1
		echo "MPAS-JEDI installation selected (experimental)."
		break
		;;
	"No")
		export MPAS_PICK_JEDI=0
		echo "Skipping MPAS-JEDI installation."
		break
		;;
	*)
		echo "Invalid selection. Please choose 1 or 2."
		;;
	esac
done
	echo ""
fi

# MPI graph partitioning (Metis gpmetis) - required to run any core in parallel
echo "--------------------------------------------------"
echo "Would you like to install Metis (gpmetis) for MPI graph partitioning?"
echo "(Strongly recommended: needed to create *.graph.info.<N> partition files"
echo "when running any MPAS core on multiple MPI tasks.)"
PS3="Enter your choice (1 for Yes, 2 for No): "
options=("Yes" "No")
select answer in "${options[@]}"; do
	case $answer in
	"Yes")
		export MPAS_METIS=1
		echo "Metis will be built from source."
		break
		;;
	"No")
		export MPAS_METIS=0
		echo "Skipping Metis installation."
		break
		;;
	*)
		echo "Invalid selection. Please choose 1 or 2."
		;;
	esac
done
echo ""

# MPAS-Limited-Area
echo "--------------------------------------------------"
echo "Would you like to install MPAS-Limited-Area? (Recommended for"
echo "regional / limited-area MPAS-Atmosphere simulations.)"
echo "It creates regional grid + init files from global MPAS meshes."
printf '\e]8;;https://github.com/MPAS-Dev/MPAS-Limited-Area\e\\MPAS-Limited-Area repository (right click to open link)\e]8;;\e\\\n'
PS3="Enter your choice (1 for Yes, 2 for No): "
options=("Yes" "No")
select answer in "${options[@]}"; do
	case $answer in
	"Yes")
		export MPAS_LIMITED_AREA=1
		echo "MPAS-Limited-Area will be installed."
		break
		;;
	"No")
		export MPAS_LIMITED_AREA=0
		echo "Skipping MPAS-Limited-Area installation."
		break
		;;
	*)
		echo "Invalid selection. Please choose 1 or 2."
		;;
	esac
done
echo ""

# MPAS python tools (mpas_tools / geometric_features / pyremap)
echo "--------------------------------------------------"
echo "Would you like to install the MPAS Python tooling stack?"
echo "(mpas_tools, geometric_features, pyremap - used for mesh creation,"
echo "masks/remapping and geometric feature definitions.)"
echo "Installed into a dedicated python environment (conda env 'mpas' if"
echo "conda/mamba is available, otherwise a venv; pyremap's full functionality"
echo "prefers conda because of the esmpy dependency)."
printf '\e]8;;https://github.com/MPAS-Dev/MPAS-Tools\e\\MPAS-Tools\e]8;;\e\\  '
printf '\e]8;;https://github.com/MPAS-Dev/geometric_features\e\\geometric_features\e]8;;\e\\  '
printf '\e]8;;https://github.com/MPAS-Dev/pyremap\e\\pyremap\e]8;;\e\\\n'
PS3="Enter your choice (1 for Yes, 2 for No): "
options=("Yes" "No")
select answer in "${options[@]}"; do
	case $answer in
	"Yes")
		export MPAS_PYTOOLS=1
		echo "MPAS Python tooling stack will be installed."
		break
		;;
	"No")
		export MPAS_PYTOOLS=0
		echo "Skipping MPAS Python tooling stack."
		break
		;;
	*)
		echo "Invalid selection. Please choose 1 or 2."
		;;
	esac
done
echo ""

# MPAS-Data (static physical tables + static geographic datasets)
echo "--------------------------------------------------"
echo "Would you like to download the MPAS static datasets? (Optional)"
echo "- MPAS-Data repository (static physical tables for MPAS-Atmosphere)"
echo "- mpas_static.tar.bz2 (~2 GB: topography, land fraction, soil types)"
echo "- Monthly climatological aerosol dataset (QNWFA_QNIFA_SIGMA_MONTHLY.dat)"
echo "(Required to run real-data MPAS-Atmosphere simulations from stand-alone"
echo "run directories.)"
printf '\e]8;;https://mpas-dev.github.io/atmosphere/atmosphere_download.html\e\\MPAS-Atmosphere data page (right click to open link)\e]8;;\e\\\n'
PS3="Enter your choice (1 for Yes, 2 for No): "
options=("Yes" "No")
select answer in "${options[@]}"; do
	case $answer in
	"Yes")
		export MPAS_STATIC_DATA=1
		echo "MPAS static datasets will be downloaded."
		break
		;;
	"No")
		export MPAS_STATIC_DATA=0
		echo "Skipping download of MPAS static datasets."
		break
		;;
	*)
		echo "Invalid selection. Please choose 1 or 2."
		;;
	esac
done
echo ""

############################### Folder layout ##############################
if [ "$COMPILER" = "Intel" ]; then
	export MPAS_FOLDER="$HOME/MPAS_Intel"
else
	export MPAS_FOLDER="$HOME/MPAS_GNU"
fi

mkdir -p "$MPAS_FOLDER"/Downloads
mkdir -p "$MPAS_FOLDER"/Libs
mkdir -p "$MPAS_FOLDER"/bin
mkdir -p "$MPAS_FOLDER"/Logs
mkdir -p "$MPAS_FOLDER"/tests/compat
mkdir -p "$MPAS_FOLDER"/data

log "Installation folder: $MPAS_FOLDER"

DIR="$MPAS_FOLDER/Libs"
export MPAS_BASE="$DIR/base" # zlib + hdf5 + pnetcdf live here
export NETCDF="$DIR/NETCDF"

# Threads for compilation
CPU_CORE=$(nproc)
export CPU_QUARTER=$(($CPU_CORE / 4))
export CPU_6CORE="6"
if [ $CPU_CORE -le $CPU_6CORE ]; then
	export CPU_QUARTER_EVEN="2"
else
	export CPU_QUARTER_EVEN=$(($CPU_CORE / 2))
fi
echo "Using ${CPU_QUARTER_EVEN} of ${CPU_CORE} cores for compilation (make -j${CPU_QUARTER_EVEN})."

############################# Basic Package Management #####################
if [ "$SYSTEMOS" = "Linux" ]; then
	log "Installing system packages with apt"
	echo "$PASSWD" | sudo -S apt -y update
	echo "$PASSWD" | sudo -S apt -y upgrade
	echo "$PASSWD" | sudo -S apt -y install build-essential bison byacc cmake curl \
		file flex g++ gawk gcc gfortran git ksh libcurl4-gnutls-dev libncurses6 \
		libncursesw5-dev libtool libxml2 m4 make perl pkg-config python3 \
		python3-dev python3-pip python3-venv time unzip wget zlib1g-dev libbz2-dev \
		libffi-dev libreadline-dev libssl-dev
	# Matching C++ headers for the installed g++ (same guard as WRF-MOSIT)
	GCC_LIB_DIR="/usr/lib/gcc/x86_64-linux-gnu"
	if [ -d "$GCC_LIB_DIR" ]; then
		HIGHEST_GCC_MAJOR=$(ls "$GCC_LIB_DIR" | sort -V | tail -n 1)
		if [ ! -d "/usr/include/c++/${HIGHEST_GCC_MAJOR}" ]; then
			echo "Missing matching C++ headers for GCC ${HIGHEST_GCC_MAJOR}"
			echo "$PASSWD" | sudo -S apt -y install "g++-${HIGHEST_GCC_MAJOR}" "libstdc++-${HIGHEST_GCC_MAJOR}-dev"
		fi
	fi
	if [ "$MPAS_PICK_JEDI" = "1" ]; then
		echo "$PASSWD" | sudo -S apt -y install git-lfs
	fi
	die_on_err "apt package install"
else
	log "Installing system packages with dnf"
	echo "$PASSWD" | sudo -S dnf install -y epel-release
	echo "$PASSWD" | sudo -S dnf -y update
	echo "$PASSWD" | sudo -S dnf -y upgrade
	echo "$PASSWD" | sudo -S dnf -y install bison bzip2 bzip2-devel cmake cpp curl \
		curl-devel flex gcc gcc-c++ gcc-gfortran git libstdc++ libstdc++-devel \
		libxml2-devel m4 make ncurses-devel perl pkgconfig python3 python3-devel \
		python3-pip tar time unzip wget which zlib-devel
	if [ "$MPAS_PICK_JEDI" = "1" ]; then
		echo "$PASSWD" | sudo -S dnf install -y git-lfs
	fi
	die_on_err "dnf package install"
fi

# Intel oneAPI repo (experimental)
if [ "$COMPILER" = "Intel" ]; then
	log "Setting up Intel oneAPI compilers (EXPERIMENTAL)"
	if [ ! -d /opt/intel/oneapi ]; then
		wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB |
			gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg >/dev/null
		echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" |
			sudo tee /etc/apt/sources.list.d/oneAPI.list
		echo "$PASSWD" | sudo -S apt -y update
		echo "$PASSWD" | sudo -S apt -y install intel-oneapi-compiler-fortran \
			intel-oneapi-compiler-dpcpp-cpp-and-cpp-classic
		die_on_err "Intel oneAPI install"
	fi
	if [ -f /opt/intel/oneapi/setvars.sh ]; then
		# shellcheck disable=SC1091
		source /opt/intel/oneapi/setvars.sh
	fi
fi

# No more sudo commands until the (optional) JEDI section, which uses
# non-interactive sudo. Clear the password from the environment now.
if [ -n "$PASSWD" ]; then
	unset PASSWD
fi

# Compiler-specific exports
if [ "$COMPILER" = "Intel" ]; then
	export CC=icx
	export CXX=icpx
	export FC=ifx
	export F90=ifx
	export F77=ifx
else
	export CC=gcc
	export CXX=g++
	export FC=gfortran
	export F90=gfortran
	export F77=gfortran
fi

export fallow_argument="-fallow-argument-mismatch"
# gfortran < 10 does not know -fallow-argument-mismatch -> probe with a tiny
# Fortran program (unrecognized options make the compiler exit non-zero)
printf 'program probe\nend program probe\n' >"${TMPDIR:-/tmp}/mpas_fflags_probe.f90"
if ${FC} ${fallow_argument} -o /dev/null "${TMPDIR:-/tmp}/mpas_fflags_probe.f90" >/dev/null 2>&1; then
	export FFLAGS="${fallow_argument}"
	export FCFLAGS="${fallow_argument}"
else
	export FFLAGS=""
	export FCFLAGS=""
fi
rm -f "${TMPDIR:-/tmp}/mpas_fflags_probe.f90"

############ Helper: build a from-source dependency library #################
build_from_source() {
	# usage: build_from_source <name> <tarball_file> <extracted_dir> <configure_or_cmake_cmd> [installed_marker]
	local name="$1" tarball="$2" extracted="$3" confcmd="$4" marker="$5"
	local logdir="${MPAS_FOLDER}/Logs/${name}"
	if [ -n "$marker" ] && [ -f "$marker" ]; then
		echo "${name} already installed (${marker}); skipping rebuild."
		return 0
	fi
	mkdir -p "$logdir"
	log "Building ${name} from source"
	cd "${MPAS_FOLDER}/Downloads" || return 1
	env -u LD_LIBRARY_PATH tar -xf "$tarball" 2>>"${logdir}/extract.log" || { die_on_err "extract ${name}"; }
	cd "$extracted" || return 1
	eval "${confcmd}" >"${logdir}/configure.log" 2>&1 || {
		tail -n 40 "${logdir}/configure.log"
		die_on_err "configure ${name}"
	}
	make -j ${CPU_QUARTER_EVEN} >"${logdir}/make.log" 2>&1 || {
		tail -n 40 "${logdir}/make.log"
		die_on_err "make ${name}"
	} 
	make -j ${CPU_QUARTER_EVEN} install >"${logdir}/make.install.log" 2>&1 || {
		tail -n 40 "${logdir}/make.install.log"
		die_on_err "make install ${name}"
	}
	echo "${name} built and installed successfully."
}

########################## Download source tarballs ##########################
log "Downloading source tarballs"
cd "${MPAS_FOLDER}/Downloads" || exit 1
wget -c https://zlib.net/fossils/zlib-${Zlib_Version}.tar.gz
wget -c https://github.com/pmodels/mpich/releases/download/v${Mpich_Version}/mpich-${Mpich_Version}.tar.gz
wget -c https://github.com/HDFGroup/hdf5/releases/download/hdf5_${HDF5_Version}/hdf5-${HDF5_Version}.tar.gz
wget -c https://parallel-netcdf.github.io/Release/pnetcdf-${Pnetcdf_Version}.tar.gz
wget -c https://github.com/Unidata/netcdf-c/archive/refs/tags/v${Netcdf_C_Version}.tar.gz
wget -c https://github.com/Unidata/netcdf-fortran/archive/refs/tags/v${Netcdf_Fortran_Version}.tar.gz
if [ "$MPAS_METIS" = "1" ]; then
	# The official METIS mirrors (glaros/INRIA) are unreliable; the Debian
	# orig tarball is the same upstream 5.1.0 source and is reliably mirrored.
	wget -c http://deb.debian.org/debian/pool/main/m/metis/metis_${Metis_Version}.dfsg.orig.tar.xz ||
		wget -c https://dl.gforge.inria.fr/metis/Metis-${Metis_Version}.tar.gz ||
		wget -c http://glaros.dtc.umn.edu/gkhome/fetch/sw/metis/METIS-${Metis_Version}.tar.gz ||
		die_on_err "METIS download (mirrors unreachable)"
fi
die_on_err "source tarball downloads"

############################## 1 zlib ###############################
build_from_source "zlib" "zlib-${Zlib_Version}.tar.gz" "zlib-${Zlib_Version}" \
	"./configure --prefix=${MPAS_BASE} CFLAGS='-O3 -fPIC' CC=gcc" \
	"${MPAS_BASE}/include/zlib.h"
export ZLIB_ROOT="${MPAS_BASE}"

############################## 2 MPICH ###############################
# F90= due to compiler issues with mpich install (same as WRF-MOSIT)
export LDFLAGS="-L${MPAS_BASE}/lib"
export CPPFLAGS="-I${MPAS_BASE}/include"
if [ "$COMPILER" = "Intel" ]; then
	MPI_CC="icx"
	MPI_CXX="icpx"
	MPI_FC="ifx"
	MPI_CONF_OPTS="FCFLAGS=-nofortran"
else
	MPI_CC=gcc MPI_CXX=g++ MPI_FC=gfortran MPI_CONF_OPTS="F90="
fi
build_from_source "mpich" "mpich-${Mpich_Version}.tar.gz" "mpich-${Mpich_Version}" \
	"env F90= CC=$MPI_CC CXX=$MPI_CXX FC=$MPI_FC ./configure --prefix=${DIR}/MPICH --with-device=ch3" \
	"${DIR}/MPICH/bin/mpicc"

export PATH=${DIR}/MPICH/bin:$PATH
export MPICC=${DIR}/MPICH/bin/mpicc
export MPICXX=${DIR}/MPICH/bin/mpicxx
export MPIFC=${DIR}/MPICH/bin/mpifort
export MPIF77=${DIR}/MPICH/bin/mpifort
export MPIF90=${DIR}/MPICH/bin/mpifort
export MPILIBS=${DIR}/MPICH/lib

############################## 3 HDF5 (parallel + fortran) ###############################
build_from_source "hdf5" "hdf5-${HDF5_Version}.tar.gz" "hdf5-${HDF5_Version}" \
	"env CC=${MPICC} FC=${MPIFC} F77=${MPIF77} F90=${MPIF90} CXX=${MPICXX} \
		CFLAGS='-O3 -fPIC' FFLAGS='${FFLAGS}' FCFLAGS='${FFLAGS}' \
		./configure --prefix=${MPAS_BASE} --with-zlib=${MPAS_BASE} \
		--enable-hl --enable-fortran --enable-parallel" \
	"${MPAS_BASE}/include/hdf5.h"
export HDF5=${MPAS_BASE}
export HDF5_ROOT=${MPAS_BASE}
export PATH=${MPAS_BASE}/bin:$PATH

############################## 4 Parallel-netCDF (pnetcdf) ###############################
build_from_source "pnetcdf" "pnetcdf-${Pnetcdf_Version}.tar.gz" "pnetcdf-${Pnetcdf_Version}" \
	"env CC=${MPICC} FC=${MPIFC} F77=${MPIF77} F90=${MPIF90} CXX=${MPICXX} \
		CFLAGS='${CFLAGS}' FFLAGS='${FFLAGS}' FCFLAGS='${FFLAGS}' \
		./configure --prefix=${MPAS_BASE} --enable-static --enable-shared" \
	"${MPAS_BASE}/include/pnetcdf.h"
export PNETCDF=${MPAS_BASE}
export PNETCDF_DIR=${MPAS_BASE}
export PNETCDF_ROOT=${MPAS_BASE}

############################## 5 NetCDF-C ###############################
build_from_source "netcdf-c" "v${Netcdf_C_Version}.tar.gz" "netcdf-c-${Netcdf_C_Version}" \
	"env CPPFLAGS='-I${MPAS_BASE}/include ${CPPFLAGS}' \
		LDFLAGS='-L${MPAS_BASE}/lib -Wl,-rpath,${MPAS_BASE}/lib' \
		LIBS='-lhdf5_hl -lhdf5 -lz -lm -lpnetcdf' \
		CC=${MPICC} FC=${MPIFC} F90=${MPIF90} F77=${MPIF77} CXX=${MPICXX} \
		./configure --prefix=${NETCDF} --disable-dap --enable-netcdf-4 \
		--enable-netcdf4 --enable-pnetcdf --enable-cdf5 --enable-parallel-tests \
		--enable-logging" \
	"${NETCDF}/lib/libnetcdf.a"
export NETCDF_INC=${NETCDF}/include
export NETCDF_LIB=${NETCDF}/lib
export NETCDF_ROOT=${NETCDF}
export NetCDF_ROOT=${NETCDF}
export LD_LIBRARY_PATH=${MPAS_BASE}/lib:${NETCDF}/lib:${DIR}/MPICH/lib:$LD_LIBRARY_PATH
export PATH=${NETCDF}/bin:$PATH

############################## 6 NetCDF-Fortran ###############################
build_from_source "netcdf-fortran" "v${Netcdf_Fortran_Version}.tar.gz" "netcdf-fortran-${Netcdf_Fortran_Version}" \
	"env LD_LIBRARY_PATH=${NETCDF}/lib:${MPAS_BASE}/lib:\$LD_LIBRARY_PATH \
		CPPFLAGS='-I${NETCDF}/include -I${MPAS_BASE}/include' \
		LDFLAGS='-L${NETCDF}/lib -L${MPAS_BASE}/lib -Wl,-rpath,${NETCDF}/lib -Wl,-rpath,${MPAS_BASE}/lib' \
		LIBS='-lnetcdf -lhdf5_hl -lhdf5 -lz -lm -ldl -lpnetcdf' \
		CC=${MPICC} FC=${MPIFC} F90=${MPIF90} F77=${MPIF77} CXX=${MPICXX} \
		./configure --prefix=${NETCDF} --enable-netcdf-4 --enable-netcdf4 \
		--enable-parallel-tests --enable-logging" \
	"${NETCDF}/lib/libnetcdff.a"

############################## 7 METIS (gpmetis) ###############################
if [ "$MPAS_METIS" = "1" ]; then
	METIS_DIR="${DIR}/METIS"
	if [ -x "${METIS_DIR}/bin/gpmetis" ]; then
		echo "METIS ${Metis_Version} already installed: ${METIS_DIR}/bin/gpmetis (skipping build)"
		log "Skipping METIS build"
	else
	log "Building METIS ${Metis_Version} from source (gpmetis)"
	mkdir -p "$METIS_DIR"
	cd "${MPAS_FOLDER}/Downloads" || exit 1
	# Autodetect whichever metis tarball actually got downloaded
	metis_tarball=""
	for cand in "metis_${Metis_Version}.dfsg.orig.tar.xz" "Metis-${Metis_Version}.tar.gz" "METIS-${Metis_Version}.tar.gz"; do
		if [ -f "$cand" ]; then metis_tarball="$cand"; break; fi
	done
	[ -n "$metis_tarball" ] || die_on_err "metis tarball not found in Downloads"
	env -u LD_LIBRARY_PATH tar -xf "$metis_tarball" 2>/dev/null || die_on_err "extract metis"
	metis_dir=""
	for d in metis-${Metis_Version} Metis-${Metis_Version} METIS-${Metis_Version}; do
		if [ -d "$d" ]; then metis_dir="$d"; break; fi
	done
	[ -n "$metis_dir" ] || die_on_err "metis extracted directory not found"
	metis_src_abs="${MPAS_FOLDER}/Downloads/${metis_dir}"
	(cd "$metis_dir" &&
		# METIS 5.1.0 predates CMake >= 3.10; patch the declared minimum and
		# pass an ABSOLUTE GKLIB_PATH (CMake 4 try_compile rejects relative paths)
		sed -i -E 's/cmake_minimum_required\(VERSION [0-9.]+\)/cmake_minimum_required(VERSION 3.10)/' \
			CMakeLists.txt GKlib/CMakeLists.txt 2>/dev/null || true
		mkdir -p build && cd build &&
		cmake -DGKLIB_PATH="${metis_src_abs}/GKlib" \
			-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
			-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${METIS_DIR}" .. &&
			make -j ${CPU_QUARTER_EVEN} && make install) \
			>"${MPAS_FOLDER}/Logs/METIS_build.log" 2>&1 || die_on_err "METIS build"
	fi
	echo "gpmetis installed to ${METIS_DIR}/bin/gpmetis"
else
	echo "Skipping METIS build (MPAS_METIS=0)."
fi

########################### Environment compatibility tests ###############################
log "Testing compiler/NetCDF environment (MPAS dependency tests)"
if [ "$COMPILER" = "Intel" ]; then
	TCC=icx
	TFC=ifx
else
	TCC=gcc
	TFC=gfortran
fi

cp "${NETCDF}/include/netcdf.inc" "${MPAS_FOLDER}/tests/compat/" 2>/dev/null
cat >"${MPAS_FOLDER}/tests/compat/pnetcdf_test.c" <<'EOF'
#include <pnetcdf.h>
#include <mpi.h>
#include <stdio.h>
int main() {
	int err, ncid;
	MPI_Init(NULL, NULL);
	err = ncmpi_create(MPI_COMM_WORLD, "foo.nc", NC_NOCLOBBER, MPI_INFO_NULL, &ncid);
	if (err == NC_NOERR) { ncmpi_enddef(ncid); ncmpi_close(ncid); printf("PASS pnetcdf test\n"); }
	else { printf("FAIL pnetcdf test\n"); }
	MPI_Finalize();
	return 0;
}
EOF
(TCC_=$TCC; TF_=$TFC;
 $CC -c "${MPAS_FOLDER}/tests/compat/pnetcdf_test.c" -I${PNETCDF}/include -I${DIR}/MPICH/include \
	-o "${MPAS_FOLDER}/tests/compat/pnetcdf_test.o" &&
	$CC "${MPAS_FOLDER}/tests/compat/pnetcdf_test.o" -o "${MPAS_FOLDER}/tests/compat/pnetcdf_test" \
	-L${PNETCDF}/lib -lpnetcdf -L${DIR}/MPICH/lib -lmpi &&
	${DIR}/MPICH/bin/mpirun -np 1 "${MPAS_FOLDER}/tests/compat/pnetcdf_test") \
	>"${MPAS_FOLDER}/Logs/pnetcdf_test.log" 2>&1 && grep -q PASS "${MPAS_FOLDER}/Logs/pnetcdf_test.log"
if [ $? -eq 0 ]; then
	echo "PnetCDF/MPI compatibility test PASSED"
else
	echo -e "\e[31mPnetCDF/MPI compatibility test FAILED - see ${MPAS_FOLDER}/Logs/pnetcdf_test.log\e[0m"
	read -r -p "Continue anyway? Type YES to continue: " cont
	[[ "$cont" != "YES" ]] && exit 1
fi

cat >"${MPAS_FOLDER}/tests/compat/netcdf_fortran_test.f90" <<'EOF'
program test_nff
	use netcdf
	implicit none
	print *, "PASS netcdf-fortran test"
end program
EOF
($TFC -c "${MPAS_FOLDER}/tests/compat/netcdf_fortran_test.f90" \
	-I${NETCDF}/include -o "${MPAS_FOLDER}/tests/compat/netcdf_fortran_test.o" &&
	$TFC "${MPAS_FOLDER}/tests/compat/netcdf_fortran_test.o" \
	-L${NETCDF}/lib -lnetcdff -lnetcdf -o "${MPAS_FOLDER}/tests/compat/netcdf_fortran_test") \
	>"${MPAS_FOLDER}/Logs/netcdf_fortran_test.log" 2>&1 &&
	"${MPAS_FOLDER}/tests/compat/netcdf_fortran_test" >>"${MPAS_FOLDER}/Logs/netcdf_fortran_test.log" 2>&1 &&
	grep -q PASS "${MPAS_FOLDER}/Logs/netcdf_fortran_test.log"
if [ $? -eq 0 ]; then
	echo "NetCDF-Fortran compatibility test PASSED"
else
	echo -e "\e[31mNetCDF-Fortran compatibility test FAILED - see ${MPAS_FOLDER}/Logs/netcdf_fortran_test.log\e[0m"
	read -r -p "Continue anyway? Type YES to continue: " cont
	[[ "$cont" != "YES" ]] && exit 1
fi
echo "All compatibility tests completed."

############################## MPAS-Model source ###############################
log "Cloning MPAS-Model v${MPAS_VERSION}"
cd "$MPAS_FOLDER" || exit 1
if [ ! -d "$MPAS_FOLDER/MPAS-Model" ]; then
	git clone --branch "${MPAS_TAG}" "https://github.com/MPAS-Dev/MPAS-Model.git" MPAS-Model ||
		git clone "https://github.com/MPAS-Dev/MPAS-Model.git" MPAS-Model
	die_on_err "MPAS-Model clone"
else
	echo "MPAS-Model source already exists; reusing it."
fi
cd "$MPAS_FOLDER/MPAS-Model" || exit 1

check_missing_execs() {
	local missing=0
	for exe in "$@"; do
		if [ ! -x "$MPAS_FOLDER/MPAS-Model/$exe" ] && [ ! -x "$MPAS_FOLDER/bin/$exe" ]; then
			echo "Missing executable: $exe"
			missing=1
		fi
	done
	return $missing
}

rebuild_and_check() {
	local core="$1" exe="$2"
	echo "Attempting rebuild of core=${core} ..."
	make -j ${CPU_QUARTER_EVEN} ${COMPILER_TARGET} CORE=${core} ${MPAS_BUILD_OPTS} \
		2>&1 | tee -a "${MPAS_FOLDER}/Logs/build_core_${core}.log" >/dev/null
	if [ -x "$MPAS_FOLDER/MPAS-Model/${exe}" ]; then
		cp -f "$MPAS_FOLDER/MPAS-Model/${exe}" "${MPAS_FOLDER}/bin/"
		echo "Rebuild of ${core} succeeded: ${exe}"
		return 0
	fi
	return 1
}

build_mpas_core() {
	local core="$1" exe="$2"
	log "Compiling MPAS core: ${core} -> ${exe} (PRECISION=${MPAS_PRECISION})"
	cd "$MPAS_FOLDER/MPAS-Model" || return 1
	make clean >/dev/null 2>&1 || true
	echo "make -j${CPU_QUARTER_EVEN} ${COMPILER_TARGET} CORE=${core} ${MPAS_BUILD_OPTS}" \
		>"${MPAS_FOLDER}/Logs/build_core_${core}.log"
	if ! make -j ${CPU_QUARTER_EVEN} ${COMPILER_TARGET} CORE=${core} ${MPAS_BUILD_OPTS} \
		2>&1 | tee -a "${MPAS_FOLDER}/Logs/build_core_${core}.log"; then
		echo "First build attempt failed. Retrying with AUTOCLEAN=true ..."
		if ! make -j ${CPU_QUARTER_EVEN} ${COMPILER_TARGET} CORE=${core} ${MPAS_BUILD_OPTS} AUTOCLEAN=true \
			2>&1 | tee -a "${MPAS_FOLDER}/Logs/build_core_${core}.log" >/dev/null; then
			echo -e "\e[31mERROR building core ${core}. See ${MPAS_FOLDER}/Logs/build_core_${core}.log\e[0m"
			die_on_err "MPAS core ${core}"
		fi
	fi
	if [ ! -x "$MPAS_FOLDER/MPAS-Model/${exe}" ]; then
		rebuild_and_check "$core" "$exe" || die_on_err "MPAS core ${core} missing executable"
	fi
	cp -f "$MPAS_FOLDER/MPAS-Model/$exe" "${MPAS_FOLDER}/bin/"
	# Keep physics tables (atmosphere post_build symlinks) resolvable in bin copies
	echo "Installed ${exe} -> ${MPAS_FOLDER}/bin/${exe}"
}

export NETCDF PNETCDF
export MPAS_BUILD_OPTS="PRECISION=${MPAS_PRECISION}"

if [ "$MPAS_PICK_ATM" = "1" ]; then
	build_mpas_core "init_atmosphere" "init_atmosphere_model"
	build_mpas_core "atmosphere" "atmosphere_model"
fi
if [ "$MPAS_PICK_OCEAN" = "1" ]; then
	build_mpas_core "ocean" "ocean_model"
fi
if [ "$MPAS_PICK_SEAICE" = "1" ]; then
	build_mpas_core "seaice" "seaice_model"
fi
if [ "$MPAS_PICK_LANDICE" = "1" ]; then
	build_mpas_core "landice" "landice_model"
fi

# Physics table symlinks (atmosphere): replicate them into bin/ for copies
if [ "$MPAS_PICK_ATM" = "1" ]; then
	(cd "$MPAS_FOLDER/MPAS-Model" &&
		for f in *TBL *DATA*; do [ -e "$f" ] && cp -f "$f" "${MPAS_FOLDER}/bin/" 2>/dev/null; done) || true
fi

############################## Helper repos ################################
if [ "$MPAS_LIMITED_AREA" = "1" ]; then
	log "Installing MPAS-Limited-Area"
	mkdir -p "$MPAS_FOLDER/tools"
	cd "$MPAS_FOLDER/tools" || exit 1
	if [ ! -d MPAS-Limited-Area ]; then
		git clone https://github.com/MPAS-Dev/MPAS-Limited-Area.git
		die_on_err "MPAS-Limited-Area clone"
	fi
	chmod +x MPAS-Limited-Area/create_region 2>/dev/null || true
	# Minimal deps: numpy + netCDF4 (cartopy/matplotlib only for plotting is optional)
	python3 -c "import numpy, netCDF4" >/dev/null 2>&1 || {
		echo "Installing python deps numpy/netCDF4 for MPAS-Limited-Area..."
		pip3 install --user numpy netCDF4 2>/dev/null ||
			pip3 install --user --break-system-packages numpy netCDF4 2>/dev/null ||
			echo "WARNING: could not pip-install numpy/netCDF4. Install them manually."
	}
	export MPAS_LIMITED_AREA_DIR="$MPAS_FOLDER/tools/MPAS-Limited-Area"
	echo "MPAS-Limited-Area ready: ${MPAS_LIMITED_AREA_DIR}/create_region"
fi

if [ "$MPAS_STATIC_DATA" = "1" ]; then
	log "Downloading MPAS-Data + static datasets"
	mkdir -p "$MPAS_FOLDER/data"
	cd "$MPAS_FOLDER/data" || exit 1
	if [ ! -d MPAS-Data ]; then
		git clone https://github.com/MPAS-Dev/MPAS-Data.git
		die_on_err "MPAS-Data clone"
	fi
	if [ ! -f mpas_static.tar.bz2 ]; then
		wget -c https://www2.mmm.ucar.edu/projects/mpas/mpas_static.tar.bz2
		die_on_err "mpas_static download"
		tar -xjf mpas_static.tar.bz2
	fi
	if [ ! -f QNWFA_QNIFA_SIGMA_MONTHLY.dat ]; then
		wget -c https://www2.mmm.ucar.edu/projects/mpas/QNWFA_QNIFA_SIGMA_MONTHLY.dat
		die_on_err "QNWFA aerosol download"
	fi
	export MPAS_STATIC_DATA_DIR="$MPAS_FOLDER/data"
	echo "Static data downloaded to $MPAS_STATIC_DATA_DIR"
fi

############################## Python tooling stack ###############################
if [ "$MPAS_PYTOOLS" = "1" ]; then
	log "Installing MPAS Python tooling (mpas_tools, geometric_features, pyremap)"
	CONDA_CMD=""
	command -v mamba >/dev/null 2>&1 && CONDA_CMD="mamba"
	[ -z "$CONDA_CMD" ] && command -v conda >/dev/null 2>&1 && CONDA_CMD="conda"

	if [ -n "$CONDA_CMD" ]; then
		if $CONDA_CMD env list 2>/dev/null | awk '{print $1}' | grep -qx "mpas"; then
			echo "Conda env 'mpas' already exists; skipping creation. Activate with: conda activate mpas"
		else
		echo "Using ${CONDA_CMD} to create the 'mpas' conda environment (conda-forge)."
		$CONDA_CMD create -y -n mpas -c conda-forge python=3.11 mpas_tools geometric_features pyremap \
			>"${MPAS_FOLDER}/Logs/conda_env_mpas.log" 2>&1
		if [ $? -eq 0 ]; then
			echo "Conda env 'mpas' created. Activate with: conda activate mpas"
		else
			echo "WARNING: conda env creation failed. See ${MPAS_FOLDER}/Logs/conda_env_mpas.log"
			echo "Falling back to cloning the repositories."
			CONDA_CMD=""
		fi
		fi
	fi
	if [ -z "$CONDA_CMD" ]; then
		mkdir -p "$MPAS_FOLDER/tools"
		cd "$MPAS_FOLDER/tools"
		git clone https://github.com/MPAS-Dev/MPAS-Tools.git 2>/dev/null
		git clone https://github.com/MPAS-Dev/geometric_features.git 2>/dev/null
		git clone https://github.com/MPAS-Dev/pyremap.git 2>/dev/null
		python3 -m venv "$MPAS_FOLDER/tools/venv-mpas" 2>/dev/null &&
			(
				source "$MPAS_FOLDER/tools/venv-mpas/bin/activate"
				pip install -U pip
				pip install ./MPAS-Tools || true
				pip install ./geometric_features ./pyremap || pip install ./geometric_features || true
				deactivate
			)
		echo "NOTE: pyremap full remapping needs the esmpy package, only easily"
		echo "available via conda-forge (esmpf builds via pip are not provided)."
	fi
fi

############################## MPAS-JEDI (experimental) ###############################
if [ "$MPAS_PICK_JEDI" = "1" ]; then
	log "Installing MPAS-JEDI via mpas-bundle (EXPERIMENTAL)"
	JEDI_DIR="$MPAS_FOLDER/jedi"
	mkdir -p "$JEDI_DIR"

	MAMBA_BIN=""
	if command -v mamba >/dev/null 2>&1; then MAMBA_BIN="mamba"; fi
	[ -z "$MAMBA_BIN" ] && command -v conda >/dev/null 2>&1 && MAMBA_BIN="conda"
	if [ -z "$MAMBA_BIN" ]; then
		echo "No conda/mamba found; installing Miniforge into ${MPAS_FOLDER}/tools/miniforge3"
		mkdir -p "$MPAS_FOLDER/tools"
		cd "$MPAS_FOLDER/tools"
		wget -c "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh" \
			-O Miniforge3.sh && bash Miniforge3.sh -b -p "$MPAS_FOLDER/tools/miniforge3"
		MAMBA_BIN="$MPAS_FOLDER/tools/miniforge3/bin/mamba"
		[ -x "$MAMBA_BIN" ] || MAMBA_BIN="$MPAS_FOLDER/tools/miniforge3/bin/conda"
		die_on_err "Miniforge install"
	fi

	git lfs install || sudo apt -y install git-lfs || sudo dnf install -y git-lfs || true

	MAMBA_BASE="$(dirname "$(dirname "$MAMBA_BIN")")"
	CONDA_SH="${MAMBA_BASE}/etc/profile.d/conda.sh"
	if $MAMBA_BIN env list 2>/dev/null | awk '{print $1}' | grep -qx "jedi"; then
		echo "Conda env 'jedi' already exists; skipping creation."
		JEDI_ENV_OK=0
	else
	echo "Creating conda env 'jedi' with JEDI stack from conda-forge..."
	$MAMBA_BIN create -y -n jedi -c conda-forge \
		"python=3.11" "cmake" "make" "ninja" "git-lfs" \
		"gfortran" "gcc" "gxx" "mpich" \
		ecbuild eckit fckit atlas oops vader saber ioda ufo crtm \
		>"${MPAS_FOLDER}/Logs/conda_env_jedi.log" 2>&1
	JEDI_ENV_OK=$?
	fi
	if [ $JEDI_ENV_OK -ne 0 ]; then
		echo -e "\e[31mWARNING: jedi env creation failed. See ${MPAS_FOLDER}/Logs/conda_env_jedi.log\e[0m"
	else
		JEDI_SRC="$JEDI_DIR/mpas-bundle"
		JEDI_BUILD="$JEDI_DIR/mpas-bundle-build"
		if [ ! -d "$JEDI_SRC" ]; then
			git clone https://github.com/JCSDA/mpas-bundle.git "$JEDI_SRC"
		fi
		mkdir -p "$JEDI_BUILD" && cd "$JEDI_BUILD"
		if $MAMBA_BIN run -n jedi bash -c "
			[ -f '$CONDA_SH' ] && source '$CONDA_SH' && conda activate jedi;
			cmake '$JEDI_SRC' -DCMAKE_BUILD_TYPE=Release -DMPAS_DOUBLE_PRECISION=ON -DBUILD_IODA_CONVERTERS=OFF" \
			>"${MPAS_FOLDER}/Logs/jedi_cmake.log" 2>&1; then
			echo "mpas-bundle configured. Building (this takes a long time)..."
			$MAMBA_BIN run -n jedi bash -c "
				[ -f '$CONDA_SH' ] && source '$CONDA_SH' && conda activate jedi;
				make -j${CPU_QUARTER_EVEN}" \
				>"${MPAS_FOLDER}/Logs/jedi_make.log" 2>&1
			if [ $? -eq 0 ]; then
				echo "mpas-bundle built. Binaries: ${JEDI_BUILD}/bin"
			else
				echo -e "\e[31mWARNING: mpas-bundle build failed. See ${MPAS_FOLDER}/Logs/jedi_make.log\e[0m"
			fi
		else
			echo -e "\e[31mWARNING: mpas-bundle cmake failed. See ${MPAS_FOLDER}/Logs/jedi_cmake.log (EXPERIMENTAL)\e[0m"
		fi
	fi
fi

############################## bashrc exports ###############################
BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# BEGIN MPAS-MOSIT v1.0.0 exports"
MARKER_END="# END MPAS-MOSIT v1.0.0 exports"

# Remove any previous MPAS block (idempotent re-runs)
if [ -f "$BASHRC" ] && grep -q "$MARKER_BEGIN" "$BASHRC"; then
	sed -i "/${MARKER_BEGIN//\//\\/}/,/${MARKER_END//\//\\/}/d" "$BASHRC"
fi

{
	echo ""
	echo "$MARKER_BEGIN"
	echo "export MPAS_FOLDER=\"$MPAS_FOLDER\""
	echo "export NETCDF=\"$NETCDF\""
	echo "export PNETCDF=\"$MPAS_BASE\""
	echo "export HDF5=\"$MPAS_BASE\""
	echo "export MPAS_EXE_DIR=\"\$MPAS_FOLDER/bin\""
	echo "export PATH=\"\$MPAS_FOLDER/bin:${DIR}/MPICH/bin:\$PATH\""
	if [ "$MPAS_METIS" = "1" ]; then
		echo "export PATH=\"${DIR}/METIS/bin:\$PATH\""
	fi
	echo "export LD_LIBRARY_PATH=\"${MPAS_BASE}/lib:${NETCDF}/lib:${DIR}/MPICH/lib:\$LD_LIBRARY_PATH\""
	if [ "$MPAS_LIMITED_AREA" = "1" ]; then
		echo "export MPAS_LIMITED_AREA_DIR=\"$MPAS_FOLDER/tools/MPAS-Limited-Area\""
		echo "export PATH=\"\$MPAS_LIMITED_AREA_DIR:\$PATH\""
	fi
	if [ "$MPAS_STATIC_DATA" = "1" ]; then
		echo "export MPAS_STATIC_DATA_DIR=\"$MPAS_FOLDER/data\""
	fi
	if [ "$MPAS_PICK_JEDI" = "1" ]; then
		echo "export MPAS_JEDI_DIR=\"$MPAS_FOLDER/jedi\""
	fi
	echo "$MARKER_END"
} >>"$BASHRC"

log "Installed executables summary"
ls -1 "${MPAS_FOLDER}/bin" 2>/dev/null
echo " "
if [ "$MPAS_METIS" = "1" ]; then echo "gpmetis: ${DIR}/METIS/bin/gpmetis"; fi

# shellcheck disable=SC1090
source "$BASHRC" || true

############################## Final notes ################################
echo " "
echo "--------------------------------------------------"
echo "Installation finished."
echo "Executables: ${MPAS_FOLDER}/bin/"
echo " "
echo "To run a core in parallel, partition a mesh with (example for 16 tasks):"
echo "  gpmetis -minconn -contig -niter=200 <case>.graph.info 16"
echo "which creates <case>.graph.info.16"
echo "Then: mpirun -np 16 <core>_model"
echo " "
echo "Run directories for MPAS-Atmosphere need namelist.atmosphere /"
echo "streams.atmosphere plus the physics tables (*TBL/*DATA* copied in bin/)."
echo " "
if [ "$MPAS_LIMITED_AREA" = "1" ]; then
	echo "MPAS-Limited-Area: ${MPAS_LIMITED_AREA_DIR}/create_region <region.pts> <grid.nc>"
	echo "(regions must be CONVEX when subsetting grid.nc files; see its README)."
	echo " "
fi
if [ "$MPAS_PYTOOLS" = "1" ]; then
	echo "Python tools: activate the 'mpas' conda env (or tools/venv-mpas) before"
	echo "using mpas_tools / geometric_features / pyremap."
	echo " "
fi
if [ "$MPAS_PICK_JEDI" = "1" ]; then
	echo "MPAS-JEDI build dir: ${MPAS_FOLDER}/jedi/mpas-bundle-build (EXPERIMENTAL)."
	echo "Tests: cd there, then: ctest --output-on-failure"
	echo " "
fi
echo "Please open a NEW terminal (or 'source ~/.bashrc') to use the exports."
echo "--------------------------------------------------"

cd "$HOME"
end=$(date)
END=$(date +"%s")
DIFF=$(($END - $START))
echo "Install Start Time: ${start}"
echo "Install End Time: ${end}"
echo "Install Duration: $(($DIFF / 3600)) hours $((($DIFF % 3600) / 60)) minutes $(($DIFF % 60)) seconds"
echo ""
echo ""
############################### Citation Requirement  ####################
echo " "
echo " MPAS-MOSIT (Version 1.0.0)"
echo " "
echo "It is important to note that any usage or publication that incorporates or"
echo "references this software must include a proper citation to acknowledge"
echo "the work of W. Hatheway (WRF-MOSIT) and the MPAS development teams."
echo " "
echo -e "\e[31mCitation: Hatheway, W., Snoun, H., ur Rehman, H., & Mwanthi, A. WRF-MOSIT: a modular and cross-platform tool for configuring and installing the WRF model [Computer software]. https://doi.org/10.1007/s12145-023-01136-y\e[0m"
echo " "
echo "MPAS-MOSIT is based on that design and installs: https://github.com/MPAS-Dev/MPAS-Model"
