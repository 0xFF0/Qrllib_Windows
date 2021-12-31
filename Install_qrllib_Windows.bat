@echo off
:: Download links
SET GIT_DOWNLOAD=https://github.com/git-for-windows/git/releases/download/v2.34.1.windows.1/Git-2.34.1-64-bit.exe
SET CMAKE_DOWNLOAD=https://github.com/Kitware/CMake/releases/download/v3.22.1/cmake-3.22.1-windows-x86_64.msi
SET PYTHON_DOWNLOAD=https://www.python.org/ftp/python/3.10.1/python-3.10.1-amd64.exe
SET SWIG_DOWNLOAD=https://versaweb.dl.sourceforge.net/project/swig/swigwin/swigwin-4.0.2/swigwin-4.0.2.zip 
SET NINJA_DOWNLOAD=https://github.com/ninja-build/ninja/releases/download/v1.10.2/ninja-win.zip
SET MSYS2_DOWNLOAD=https://github.com/msys2/msys2-installer/releases/download/2021-11-30/msys2-x86_64-20211130.exe


:: Download requirements
if not exist git-setup.exe ( curl -L %GIT_DOWNLOAD% --output git-setup.exe)
if not exist cmake-setup.msi ( curl -L %CMAKE_DOWNLOAD% --output cmake-setup.msi)
if not exist python-setup.exe ( curl %PYTHON_DOWNLOAD% --output python-setup.exe)
if not exist swigwin.zip ( curl %SWIG_DOWNLOAD% --output swigwin.zip)
if not exist ninja-win.zip ( curl -L %NINJA_DOWNLOAD% --output ninja-win.zip)
if not exist msys2-setup.exe ( curl -L %MSYS2_DOWNLOAD% --output msys2-setup.exe)


:: Git setup
echo ----------------------------
echo Git setup
echo ----------------------------
if exist "C:\Program Files\Git\bin\git.exe" (
  echo Exists, skipping the setup 
) else ( 
  echo [-^>] Keep the default option to use git from the command prompt.
  git-setup.exe 
)
echo.


:: Cmake setup
echo ----------------------------
echo Cmake setup
echo ----------------------------

if exist "C:\Program Files\CMake\bin\cmake.exe" (
  echo Exists, skipping the setup 
) else ( 
  echo [-^>] Select the option to add CMake to system or user PATH during the installation.
  msiexec /i cmake-setup.msi 
)
echo.

:: Python setup
echo ----------------------------
echo Python setup
echo ----------------------------
python --version 2>NUL
for /f %%i in ('python --version') do set TMPVAR=%%i
if not [%TMPVAR%] == [Python] ( 
echo [-^>] Selecting the option to 'Add Python 3.x to PATH'. 
echo [-^>] Disable the path length limit.
python-setup.exe 
) else (
  echo Exists, skipping the setup 
)
echo.

:: Swig setup
echo ----------------------------
echo Swig setup
echo ----------------------------
if exist C:\opt\swigwin\swig.exe (
  echo Exists, skipping the setup 
) else (
  mkdir c:\opt\
  tar -xf swigwin.zip -C c:\opt\
  move c:\opt\swigwin-* c:\opt\swigwin
)
echo.

:: Ninja setup
echo ----------------------------
echo Ninja setup
echo ----------------------------
if exist C:\opt\bin\ninja.exe (
  echo Exists, skipping the setup 
) else (
mkdir c:\opt\bin
tar -xf ninja-win.zip -C c:\opt\bin
)
echo.


:: MSYS2 setup
echo ----------------------------
echo MSYS2 setup
echo ----------------------------
set PATH=%PATH%;C:\msys64\usr\bin;
set PATH=%PATH%;C:\msys64\mingw64\bin;
if exist C:\msys64\mingw64\bin\gcc.exe (
  echo Exists, skipping the setup 
) else (
msys2-setup.exe in -c -t c:\msys64
bash -l -c "pacman -Syu --noconfirm"
bash -l -c "pacman -S --needed base-devel mingw-w64-x86_64-toolchain --noconfirm"
)
echo.


:: Refresh PATH
echo ----------------------------
echo Refresh PATH
echo ----------------------------
:: Get System PATH
for /f "tokens=2* skip=2" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path') do set syspath=%%A%%B
:: Get User Path
for /f "tokens=2* skip=2" %%A in ('reg query "HKCU\Environment" /v Path') do set userpath=%%A%%B
:: Set Refreshed Path
set PATH=%PATH%;%userpath%;%syspath%;
echo %PATH%
echo.



:: Clone and patch qrllib
echo ----------------------------
echo Clone and patch qrllib
echo ----------------------------
if not exist C:\src\qrllib (
  git clone --recurse https://github.com/theQRL/qrllib.git c:\src\qrllib
  cd \src\qrllib

  :: Add ninja compiler
  sed -i "s/subprocess.check_call(cmake_call/if sys.platform == 'win32':\n                cmake_call.extend(['-G' + env.get('CMAKE_VS_GENERATOR', 'Ninja')])\n            subprocess.check_call(cmake_call/g" setup.py

  :: Cmakelist patch
  sed -i "s/project(qrllib)/project(qrllib)\nIF (WIN32)\n    file(TO_CMAKE_PATH \"${CMAKE_LIBRARY_OUTPUT_DIRECTORY}\" CMAKE_LIBRARY_OUTPUT_DIRECTORY)\n    set(CMAKE_CXX_FLAGS \"${CMAKE_CXX_FLAGS} -std=c++14 -Wall -Wextra -pedantic\")\n    # Temp fix for https:\/\/sourceware.org\/bugzilla\/show_bug.cgi?id=27657\n    set(CMAKE_CXX_STANDARD_LIBRARIES -lbcrypt)\nENDIF()/g" CMakeLists.txt

  :: Patch misc.cpp to add BCryptGenRandom
  sed -i "s/#include <fstream>/#include <fstream>\n#ifdef _WIN32\n#include <wtypesbase.h>\n#include <bcrypt.h>\n#endif\n\n#ifdef _WIN32\nextern \"C\" {\n\tstd::vector<unsigned char> getBCryptGenRandom(uint32_t seed_size)\n\t{\n\t\t	std::vector<unsigned char> tmp(seed_size, 0);\n\t\tBCryptGenRandom(nullptr, tmp.data(), static_cast<ULONG>(seed_size), BCRYPT_USE_SYSTEM_PREFERRED_RNG);\n\t\treturn tmp;\n\t}\n}\n#endif/g" src/qrl/misc.cpp
  sed -i "s/std::ifstream urandom/#ifdef _WIN32\n\ttmp = getBCryptGenRandom(seed_size);\n#else\n\tstd::ifstream urandom/g" src/qrl/misc.cpp
  sed -i "s/urandom.close();/urandom.close();\n#endif/g" src/qrl/misc.cpp
  sed -i "s/#endif \/\/QRLLIB_MISC_H/#ifdef _WIN32\nextern \"C\" {\nstd::vector<unsigned char> getBCryptGenRandom(uint32_t seed_size);\n}\n#endif\n#endif \/\/QRLLIB_MISC_H/g" src/qrl/misc.h

  :: Replace uint by unsigned int in swig
  sed -i "s/%%array_class(uint, uintCArray)/%%array_class(unsigned int, uintCArray)/g" src/api/dilithium.i
  sed -i "s/%%array_class(uint, uintCArray)/%%array_class(unsigned int, uintCArray)/g" src/api/kyber.i
  sed -i "s/%%array_class(uint, uintCArray)/%%array_class(unsigned int, uintCArray)/g" src/api/pyqrllib.i

  :: Patch kyber and dilithium to add BCryptGenRandom
  curl https://raw.githubusercontent.com/theQRL/dilithium/d178c66fff79448c5195cf48c1d60831fdabb42d/ref/randombytes.c --output deps/dilithium/ref/randombytes.c
  curl https://raw.githubusercontent.com/theQRL/kyber/45e6d3f2e57707ca4ebca62f674a5375ea270901/ref/randombytes.c --output deps/kyber/ref/randombytes.c

) else (
  echo Exists, skipping the setup 
)
echo.


:: Compile qrllib
echo ----------------------------
echo Compile qrllib
echo ----------------------------
cd c:\src\qrllib
set PATH=c:\opt\bin;c:\opt\swigwin;%PATH%
set CC=gcc
set CXX=g++
py -3 setup.py install
echo.

:: Required dll for python
:: Prob, Python 3.8+ no longer searches for DLL's on the path: https://github.com/PyO3/maturin/issues/466
echo ----------------------------
echo Copying required dll for python
echo ----------------------------
copy C:\msys64\mingw64\bin\libgcc_s_seh-1.dll %USERPROFILE%\AppData\Local\Programs\Python\Python310\libgcc_s_seh-1.dll
copy C:\msys64\mingw64\bin\libwinpthread-1.dll %USERPROFILE%\AppData\Local\Programs\Python\Python310\libwinpthread-1.dll
copy "C:\msys64\mingw64\bin\libstdc++-6.dll" "%USERPROFILE%\AppData\Local\Programs\Python\Python310\libstdc++-6.dll"
echo Ready to use qrllib. Need to close cmd.exe to refresh environment variables.
echo.

pause
exit
