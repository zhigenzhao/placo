#!/bin/bash

# Check the operating system
OS_NAME=$(uname -s)
OS_VERSION=""

if [[ "$OS_NAME" == "Linux" ]]; then
    if command -v lsb_release &>/dev/null; then
        OS_VERSION=$(lsb_release -rs)
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_VERSION=$VERSION_ID
    fi
    if [[ "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
        echo "This script only supports Ubuntu 22.04 or 24.04."
        exit 1
    fi
else
    echo "Unsupported operating system: $OS_NAME"
    exit 1
fi

echo "Operating system check passed: $OS_NAME $OS_VERSION"

# Check if the --conda parameter is passed
if [[ "$1" == "--conda" ]]; then
    # Check if an environment name is provided
    if [[ -n "$2" ]]; then
        ENV_NAME="$2"
    else
        ENV_NAME="placo"
    fi

    # Detect the system's default Python version
    if command -v python3 &>/dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1)
    elif command -v python &>/dev/null; then
        PYTHON_VERSION=$(python --version 2>&1)
    else
        echo "Python is not installed on this system."
        exit 1
    fi

    echo "The system's default Python version is: $PYTHON_VERSION"

    # Extract the major and minor version numbers from the Python version string
    PYTHON_MAJOR_MINOR=$(echo $PYTHON_VERSION | grep -oP '\d+\.\d+')

    # Create a conda environment with the detected Python version
    # Initialize conda
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/anaconda3/etc/profile.d/conda.sh"
    else
        echo "Conda initialization script not found. Please install Miniconda or Anaconda."
        exit 1
    fi

    conda deactivate
    conda remove -n "$ENV_NAME" --all -y
    conda create -n "$ENV_NAME" python=$PYTHON_MAJOR_MINOR -y

    echo "Conda environment '$ENV_NAME' created with Python $PYTHON_MAJOR_MINOR"

    # Activate the conda environment
    conda activate "$ENV_NAME"

    conda deactivate

    echo -e "[INFO] Created conda environment named '$ENV_NAME'.\n"
    echo -e "\t\t1. To activate the environment, run:                conda activate $ENV_NAME"
    echo -e "\t\t2. To install the package, run:                     bash setup.sh --install"
    echo -e "\t\t3. To deactivate the environment, run:              conda deactivate"
    echo -e "\n"

# Check if the --install parameter is passed
elif [[ "$1" == "--install" ]]; then

    # Get the currently activated conda environment name
    if [[ -z "${CONDA_DEFAULT_ENV}" ]]; then
        echo "Error: No conda environment is currently activated."
        echo "Please activate a conda environment first with: conda activate <env_name>"
        exit 1
    fi
    ENV_NAME=${CONDA_DEFAULT_ENV}

    # replace conda c++ dependency with libstdcxx-ng
    if [[ "$OS_NAME" == "Linux" ]]; then
        conda install -c conda-forge libstdcxx-ng -y
    fi
    pip install --upgrade pip

    if [[ "$OS_NAME" == "Linux" ]]; then
        # install compilation tools on conda
        conda install -c conda-forge cmake make -y
    else
        echo "Unsupported operating system: $OS_NAME"
        exit 1
    fi

    # Install the required packages
    conda install -c conda-forge pinocchio=3.4.0 -y
    conda install -c conda-forge eigen protobuf jsoncpp eiquadprog jsoncpp doxygen -y
    pip install meshcat ischedule doxystub

    # # Build the package
    cd "$(dirname "$(realpath "$0")")"
    rm -rf build
    mkdir -p build
    cd build

    if [[ "$OS_NAME" == "Linux" ]]; then
        # cmake using conda installed compilers
        cmake .. \
            -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
            -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
            -DPYTHON_EXECUTABLE=$(which python) \
            -DCMAKE_BUILD_TYPE=Release
    else
        echo "Unsupported operating system: $OS_NAME"
        exit 1
    fi    


    # Use half of the available threads for building (minimum of 1)
    if [[ "$OS_NAME" == "Linux" ]]; then
        NUM_THREADS=$(($(nproc)/2))
    else
        echo "Unsupported operating system: $OS_NAME"
        exit 1
    fi
    if [ "$NUM_THREADS" -lt 1 ]; then
        NUM_THREADS=1
    fi
    make -j$NUM_THREADS
    make install

    echo -e "\n"
    echo -e "Placo is installed in conda env $ENV_NAME"
    echo -e "\n"

else
    echo "Usage: $0 [--conda <env_name>] [--install] [--clean]"
    echo "  --conda <env_name> : Create a new conda environment with the specified name."
    echo "  --install          : Install the package in the currently activated conda environment."
    exit 1
fi