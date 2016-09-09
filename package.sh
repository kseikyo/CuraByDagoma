#!/usr/bin/env bash

mkvirtualenv Cura

# This script is to package the Cura package for Windows/Linux and Mac OS X
# This script should run under Linux and Mac OS X, as well as Windows with Cygwin.

#############################
# CONFIGURATION
#############################

##Select the build target
BUILD_TARGET=${1:-none}
#BUILD_TARGET=win32
#BUILD_TARGET=darwin
#BUILD_TARGET=debian_i386
#BUILD_TARGET=debian_amd64
#BUILD_TARGET=freebsd

##Do we need to create the final archive
ARCHIVE_FOR_DISTRIBUTION=1
##Which version name are we appending to the final archive
export BUILD_NAME="Cura-by-Dagoma-Easy200"
export BUILD_NAME_INSTALL="Cura_by_Dagoma_Easy200"
TARGET_DIR=${BUILD_NAME}

##Which versions of external programs to use
WIN_PORTABLE_PY_VERSION=2.7.2.1

##Which CuraEngine to use
if [ -z ${CURA_ENGINE_REPO} ] ; then
	CURA_ENGINE_REPO="https://github.com/Ultimaker/CuraEngine"
fi

#############################
# Support functions
#############################
function checkTool
{
	if [ -z "`which $1`" ]; then
		echo "The $1 command must be somewhere in your \$PATH."
		echo "Fix your \$PATH or install $2"
		exit 1
	fi
}

function downloadURL
{
	filename=`basename "$1"`
	echo "Checking for $filename"
	if [ ! -f "$filename" ]; then
		echo "Downloading $1"
		curl -L -O "$1"
		if [ $? != 0 ]; then
			echo "Failed to download $1"
			exit 1
		fi
	fi
}

function extract
{
	echo "Extracting $*"
	echo "7z x -y $*" >> log.txt
	7z x -y $* >> log.txt
	if [ $? != 0 ]; then
        echo "Failed to extract $*"
        exit 1
	fi
}

#############################
# Actual build script
#############################
if [ "$BUILD_TARGET" = "none" ]; then
	echo "You need to specify a build target with:"
	echo "$0 win32"
	echo "$0 debian_i368"
	echo "$0 debian_amd64"
	echo "$0 darwin"
	echo "$0 freebsd"
	exit 0
fi

# Change working directory to the directory the script is in
# http://stackoverflow.com/a/246128
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR

checkTool git "git: http://git-scm.com/"
checkTool curl "curl: http://curl.haxx.se/"
if [ $BUILD_TARGET = "win32" ]; then
	#Check if we have 7zip, needed to extract and packup a bunch of packages for windows.
	checkTool 7z "7zip: http://www.7-zip.org/"
	checkTool mingw32-make "mingw: http://www.mingw.org/"
fi
#For building under MacOS we need gnutar instead of tar
if [ -z `which gnutar` ]; then
	TAR=tar
else
	TAR=gnutar
fi


#############################
# Darwin
#############################

if [ "$BUILD_TARGET" = "darwin" ]; then
    TARGET_DIR=Cura-${BUILD_NAME}-MacOS

	rm -rf scripts/darwin/build
	rm -rf scripts/darwin/dist

	python build_app.py py2app
	rc=$?
	if [[ $rc != 0 ]]; then
		echo "Cannot build app."
		exit 1
	fi

    #Add cura version file (should read the version from the bundle with pyobjc, but will figure that out later)
    echo $BUILD_NAME > scripts/darwin/dist/Cura.app/Contents/Resources/version
	#rm -rf CuraEngine
	#git clone ${CURA_ENGINE_REPO}
    #if [ $? != 0 ]; then echo "Failed to clone CuraEngine"; exit 1; fi
	#make -C CuraEngine VERSION=${BUILD_NAME}
    #if [ $? != 0 ]; then echo "Failed to build CuraEngine"; exit 1; fi
	cp CuraEngine/build/CuraEngine scripts/darwin/dist/Cura.app/Contents/Resources/CuraEngine

	cd scripts/darwin

	# Install QuickLook plugin
	mkdir -p dist/Cura.app/Contents/Library/QuickLook
	cp -a STLQuickLook.qlgenerator dist/Cura.app/Contents/Library/QuickLook/

	# Archive app
	cd dist
	$TAR cfp - Cura.app | gzip --best -c > ../../../${TARGET_DIR}.tar.gz
	cd ..

	# Create sparse image for distribution
	hdiutil detach /Volumes/${BUILD_NAME}/
	rm -rf ${BUILD_NAME}.dmg.sparseimage
	echo 'convert'
	hdiutil convert DmgTemplateCompressed.dmg -format UDSP -o ${BUILD_NAME}.dmg
	echo 'resize'
	hdiutil resize -size 500m ${BUILD_NAME}.dmg.sparseimage
	echo 'attach'
	hdiutil attach ${BUILD_NAME}.dmg.sparseimage
	echo 'cp'
	mv dist/Cura.app dist/${BUILD_NAME}.app
	cp -a dist/${BUILD_NAME}.app /Volumes/${BUILD_NAME}/
	echo 'detach'
	hdiutil detach /Volumes/${BUILD_NAME}
	echo 'convert'
	hdiutil convert ${BUILD_NAME}.dmg.sparseimage -format UDZO -imagekey zlib-level=9 -ov -o ../../${TARGET_DIR}.dmg
	exit
fi

#############################
# FreeBSD part by CeDeROM
#############################

if [ "$BUILD_TARGET" = "freebsd" ]; then
	export CXX="c++"
	rm -rf Power
	if [ ! -d "Power" ]; then
		git clone https://github.com/GreatFruitOmsk/Power
	else
		cd Power
		git pull
		cd ..
	fi
	rm -rf CuraEngine
	git clone ${CURA_ENGINE_REPO}
    if [ $? != 0 ]; then echo "Failed to clone CuraEngine"; exit 1; fi
	gmake -j4 -C CuraEngine VERSION=${BUILD_NAME}
    if [ $? != 0 ]; then echo "Failed to build CuraEngine"; exit 1; fi
	rm -rf scripts/freebsd/dist
	mkdir -p scripts/freebsd/dist/share/cura
	mkdir -p scripts/freebsd/dist/share/applications
	mkdir -p scripts/freebsd/dist/bin
	cp -a Cura scripts/freebsd/dist/share/cura/
	cp -a resources scripts/freebsd/dist/share/cura/
	cp -a plugins scripts/freebsd/dist/share/cura/
	cp -a CuraEngine/build/CuraEngine scripts/freebsd/dist/share/cura/
	cp scripts/freebsd/cura.py scripts/freebsd/dist/share/cura/
	cp scripts/freebsd/cura.desktop scripts/freebsd/dist/share/applications/
	cp scripts/freebsd/cura scripts/freebsd/dist/bin/
	cp -a Power/power scripts/freebsd/dist/share/cura/
	echo $BUILD_NAME > scripts/freebsd/dist/share/cura/Cura/version
	#Create file list (pkg-plist)
	cd scripts/freebsd/dist
	find * -type f > ../pkg-plist
	DIRLVL=20; while [ $DIRLVL -ge 0 ]; do
		DIRS=`find share/cura -type d -depth $DIRLVL`
		for DIR in $DIRS; do
			echo "@dirrm $DIR" >> ../pkg-plist
		done
		DIRLVL=`expr $DIRLVL - 1`
	done
	cd ..
	# Create archive or package if root
	if [ `whoami` == "root" ]; then
	    echo "Are you root? Use the Port Luke! :-)"
	else
	    echo "You are not root, building simple package archive..."
	    pwd
	    $TAR czf ../../${TARGET_DIR}.tar.gz dist/**
	fi
	exit
fi

#############################
# Debian 32bit .deb
#############################

if [ "$BUILD_TARGET" = "debian_i386" ]; then
    export CXX="g++ -m32"
	if [ ! -d "Power" ]; then
		git clone https://github.com/GreatFruitOmsk/Power
	else
		cd Power
		git pull
		cd ..
	fi
	rm -rf CuraEngine
	git clone ${CURA_ENGINE_REPO}
    if [ $? != 0 ]; then echo "Failed to clone CuraEngine"; exit 1; fi
	make -C CuraEngine VERSION=${BUILD_NAME}
    if [ $? != 0 ]; then echo "Failed to build CuraEngine"; exit 1; fi
	rm -rf scripts/linux/${BUILD_TARGET}/usr/share/cura
	mkdir -p scripts/linux/${BUILD_TARGET}/usr/share/cura
	cp -a Cura scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp -a resources scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp -a plugins scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp -a CuraEngine/build/CuraEngine scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp scripts/linux/cura.py scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp -a Power/power scripts/linux/${BUILD_TARGET}/usr/share/cura/
	echo $BUILD_NAME > scripts/linux/${BUILD_TARGET}/usr/share/cura/Cura/version
	sudo chown root:root scripts/linux/${BUILD_TARGET} -R
	sudo chmod 755 scripts/linux/${BUILD_TARGET}/usr -R
	sudo chmod 755 scripts/linux/${BUILD_TARGET}/DEBIAN -R
	cd scripts/linux
	dpkg-deb --build ${BUILD_TARGET} $(dirname ${TARGET_DIR})/cura_${BUILD_NAME}-${BUILD_TARGET}.deb
	sudo chown `id -un`:`id -gn` ${BUILD_TARGET} -R
	exit
fi

#############################
# Debian 64bit .deb
#############################

if [ "$BUILD_TARGET" = "debian_amd64" ]; then
    export CXX="g++ -m64"
	if [ ! -d "Power" ]; then
		git clone https://github.com/GreatFruitOmsk/Power
	else
		cd Power
		git pull
		cd ..
	fi
	rm -rf CuraEngine
	git clone ${CURA_ENGINE_REPO}
    if [ $? != 0 ]; then echo "Failed to clone CuraEngine"; exit 1; fi
	make -C CuraEngine
    if [ $? != 0 ]; then echo "Failed to build CuraEngine"; exit 1; fi
	rm -rf scripts/linux/${BUILD_TARGET}/usr/share/cura
	mkdir -p scripts/linux/${BUILD_TARGET}/usr/share/cura
	cp -a Cura scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp -a resources scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp -a plugins scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp -a CuraEngine/build/CuraEngine scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp scripts/linux/cura.py scripts/linux/${BUILD_TARGET}/usr/share/cura/
	cp -a Power/power scripts/linux/${BUILD_TARGET}/usr/share/cura/
	echo $BUILD_NAME > scripts/linux/${BUILD_TARGET}/usr/share/cura/Cura/version
	sudo chown root:root scripts/linux/${BUILD_TARGET} -R
	sudo chmod 755 scripts/linux/${BUILD_TARGET}/usr -R
	sudo chmod 755 scripts/linux/${BUILD_TARGET}/DEBIAN -R
	cd scripts/linux
	dpkg-deb --build ${BUILD_TARGET} $(dirname ${TARGET_DIR})/${BUILD_NAME}.deb
	sudo chown `id -un`:`id -gn` ${BUILD_TARGET} -R
	exit
fi

#############################
# Rest
#############################

#############################
# Download all needed files.
#############################

if [ $BUILD_TARGET = "win32" ]; then
	#Get portable python for windows and extract it. (Linux and Mac need to install python themselfs)
	downloadURL http://ftp.nluug.nl/languages/python/portablepython/v2.7/PortablePython_${WIN_PORTABLE_PY_VERSION}.exe
	downloadURL http://sourceforge.net/projects/pyserial/files/pyserial/2.5/pyserial-2.5.win32.exe
	downloadURL http://sourceforge.net/projects/pyopengl/files/PyOpenGL/3.0.1/PyOpenGL-3.0.1.win32.exe
	downloadURL http://sourceforge.net/projects/numpy/files/NumPy/1.6.2/numpy-1.6.2-win32-superpack-python2.7.exe
	downloadURL http://videocapture.sourceforge.net/VideoCapture-0.9-5.zip
	#downloadURL http://ffmpeg.zeranoe.com/builds/win32/static/ffmpeg-20120927-git-13f0cd6-win32-static.7z
	downloadURL http://sourceforge.net/projects/comtypes/files/comtypes/0.6.2/comtypes-0.6.2.win32.exe
	downloadURL http://www.uwe-sieber.de/files/ejectmedia.zip
	#Get the power module for python
	rm -rf Power
	git clone https://github.com/GreatFruitOmsk/Power
	# rm -rf CuraEngine # By Dagoma ne pas redownload CuraEngine pour win32
	# git clone ${CURA_ENGINE_REPO}
 #    if [ $? != 0 ]; then echo "Failed to clone CuraEngine"; exit 1; fi
fi

#############################
# Build the packages
#############################
rm -rf ${TARGET_DIR}
mkdir -p ${TARGET_DIR}

rm -f log.txt
if [ $BUILD_TARGET = "win32" ]; then
	#For windows extract portable python to include it.
	extract PortablePython_${WIN_PORTABLE_PY_VERSION}.exe \$_OUTDIR/App
	extract PortablePython_${WIN_PORTABLE_PY_VERSION}.exe \$_OUTDIR/Lib/site-packages
	extract pyserial-2.5.win32.exe PURELIB
	extract PyOpenGL-3.0.1.win32.exe PURELIB
	extract numpy-1.6.2-win32-superpack-python2.7.exe numpy-1.6.2-sse2.exe
	extract numpy-1.6.2-sse2.exe PLATLIB
	extract VideoCapture-0.9-5.zip VideoCapture-0.9-5/Python27/DLLs/vidcap.pyd
	#extract ffmpeg-20120927-git-13f0cd6-win32-static.7z ffmpeg-20120927-git-13f0cd6-win32-static/bin/ffmpeg.exe
	#extract ffmpeg-20120927-git-13f0cd6-win32-static.7z ffmpeg-20120927-git-13f0cd6-win32-static/licenses
	extract comtypes-0.6.2.win32.exe
	extract ejectmedia.zip Win32

	mkdir -p ${TARGET_DIR}/python
	mkdir -p ${TARGET_DIR}/Cura/
	mv \$_OUTDIR/App/* ${TARGET_DIR}/python
	mv \$_OUTDIR/Lib/site-packages/wx* ${TARGET_DIR}/python/Lib/site-packages/
	mv PURELIB/serial ${TARGET_DIR}/python/Lib
	mv PURELIB/OpenGL ${TARGET_DIR}/python/Lib
	mv PURELIB/comtypes ${TARGET_DIR}/python/Lib
	mv PLATLIB/numpy ${TARGET_DIR}/python/Lib
	mv Power/power ${TARGET_DIR}/python/Lib
	mv VideoCapture-0.9-5/Python27/DLLs/vidcap.pyd ${TARGET_DIR}/python/DLLs
	#mv ffmpeg-20120927-git-13f0cd6-win32-static/bin/ffmpeg.exe ${TARGET_DIR}/Cura/
	#mv ffmpeg-20120927-git-13f0cd6-win32-static/licenses ${TARGET_DIR}/Cura/ffmpeg-licenses/
	mv Win32/EjectMedia.exe ${TARGET_DIR}/Cura/
	
	rm -rf Power/
	rm -rf \$_OUTDIR
	rm -rf PURELIB
	rm -rf PLATLIB
	rm -rf VideoCapture-0.9-5
	rm -rf numpy-1.6.2-sse2.exe
	#rm -rf ffmpeg-20120927-git-13f0cd6-win32-static

	#Clean up portable python a bit, to keep the package size down.
	rm -rf ${TARGET_DIR}/python/PyScripter.*
	rm -rf ${TARGET_DIR}/python/Doc
	rm -rf ${TARGET_DIR}/python/locale
	rm -rf ${TARGET_DIR}/python/tcl
	rm -rf ${TARGET_DIR}/python/Lib/test
	rm -rf ${TARGET_DIR}/python/Lib/distutils
	rm -rf ${TARGET_DIR}/python/Lib/site-packages/wx-2.8-msw-unicode/wx/tools
	rm -rf ${TARGET_DIR}/python/Lib/site-packages/wx-2.8-msw-unicode/wx/locale
	#Remove the gle files because they require MSVCR71.dll, which is not included. We also don't need gle, so it's safe to remove it.
	rm -rf ${TARGET_DIR}/python/Lib/OpenGL/DLLS/gle*

    #Build the C++ engine
	# mingw32-make -C CuraEngine VERSION=${BUILD_NAME}
 #    if [ $? != 0 ]; then echo "Failed to build CuraEngine"; exit 1; fi
fi

#add Cura
mkdir -p ${TARGET_DIR}/Cura ${TARGET_DIR}/resources ${TARGET_DIR}/plugins
cp -a Cura/* ${TARGET_DIR}/Cura
cp -a resources/* ${TARGET_DIR}/resources
cp -a plugins/* ${TARGET_DIR}/plugins
#Add cura version file
echo $BUILD_NAME > ${TARGET_DIR}/Cura/version

#add script files
if [ $BUILD_TARGET = "win32" ]; then
    cp -a scripts/${BUILD_TARGET}/*.bat $TARGET_DIR/
   cp Win32CuraEngine/CuraEngine.exe $TARGET_DIR #Add by dagoma
    # cp CuraEngine/build/CuraEngine.exe $TARGET_DIR
else
    cp -a scripts/${BUILD_TARGET}/*.sh $TARGET_DIR/
fi

#package the result
if (( ${ARCHIVE_FOR_DISTRIBUTION} )); then
	if [ $BUILD_TARGET = "win32" ]; then
		#rm ${TARGET_DIR}.zip
		#cd ${TARGET_DIR}
		#7z a ../${TARGET_DIR}.zip *
		#cd ..

		# if [ ! -z `which wine` ]; then
		# 	#if we have wine, try to run our nsis script.
		# 	rm -rf scripts/win32/dist
		# 	ln -sf `pwd`/${TARGET_DIR} scripts/win32/dist
		# 	wine ~/.wine/drive_c/Program\ Files/NSIS/makensis.exe /DVERSION=${BUILD_NAME} scripts/win32/installer.nsi
  		#           if [ $? != 0 ]; then echo "Failed to package NSIS installer"; exit 1; fi
		# 	mv scripts/win32/Cura_${BUILD_NAME}.exe ./
		# fi
		if [ -f '/c/Program Files (x86)/NSIS/makensis.exe' ]; then
			rm -rf scripts/win32/dist
			mv `pwd`/${TARGET_DIR} scripts/win32/dist
			echo ${BUILD_NAME}
			'/c/Program Files (x86)/NSIS/makensis.exe' -DVERSION=${BUILD_NAME} 'scripts/win32/installer.nsi' >> log.txt
            if [ $? != 0 ]; then echo "Failed to package NSIS installer"; exit 1; fi
			mv scripts/win32/${BUILD_NAME}.exe ./
	        if [ $? != 0 ]; then echo "Can't Move Frome scripts/win32/...exe"; fi
			mv ./${BUILD_NAME}.exe ./Instal_${BUILD_NAME_INSTALL}.exe
	        if [ $? != 0 ]; then echo "Can't Move Frome ./ to ./Instal_${BUILD_NAME_INSTALL}.exe"; exit 1; fi
	        echo 'Good Job, All Works Well !!! :)'
		fi
	else
		echo "Archiving to ${TARGET_DIR}.tar.gz"
		$TAR cfp - ${TARGET_DIR} | gzip --best -c > ${TARGET_DIR}.tar.gz
	fi
else
	echo "Installed into ${TARGET_DIR}"
fi