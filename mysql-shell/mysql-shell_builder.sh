#!/bin/sh

shell_quote_string() {
    echo "$1" | sed -e 's,\([^a-zA-Z0-9/_.=-]\),\\\1,g'
}

usage () {
    cat <<EOF
Usage: $0 [OPTIONS]
    The following options may be given :
        --builddir=DIR      Absolute path to the dir where all actions will be performed
        --get_sources       Source will be downloaded from github
        --build_src_rpm     If it is 1 src rpm will be built
        --build_source_deb  If it is 1 source deb package will be built
        --build_rpm         If it is 1 rpm will be built
        --build_deb         If it is 1 deb will be built
        --build_tarball     If it is 1 tarball will be built
        --install_deps      Install build dependencies(root previlages are required)
        --branch_db         Branch for build (Percona-Server or mysql-server)
        --repo              Repo for build (Percona-Server or mysql-server)
        --repo_protobuf     Protobuf repo for build and linkage
        --repo_mysqlshell   mysql-shell repo
        --mysqlshell_branch Branch for mysql-shell
        --protobuf_branch   Branch for protobuf
        --rpm_release       RPM version( default = 1)
        --deb_release       DEB version( default = 1)
        --help) usage ;;
Example $0 --builddir=/tmp/PS80 --get_sources=1 --build_src_rpm=1 --build_rpm=1
EOF
        exit 1
}

append_arg_to_args () {
    args="$args "$(shell_quote_string "$1")
}

parse_arguments() {
    pick_args=
    if test "$1" = PICK-ARGS-FROM-ARGV
    then
        pick_args=1
        shift
    fi
    for arg do
        val=$(echo "$arg" | sed -e 's;^--[^=]*=;;')
        case "$arg" in
            # these get passed explicitly to mysqld
            --builddir=*) WORKDIR="$val" ;;
            --build_src_rpm=*) SRPM="$val" ;;
            --build_source_deb=*) SDEB="$val" ;;
            --build_rpm=*) RPM="$val" ;;
            --build_deb=*) DEB="$val" ;;
            --get_sources=*) SOURCE="$val" ;;
            --build_tarball=*) TARBALL="$val" ;;
            --branch_db=*) BRANCH="$val" ;;
            --repo=*) REPO="$val" ;;
            --install_deps=*) INSTALL="$val" ;;
            --repo_protobuf=*) PROTOBUF_REPO="$val" ;;
            --repo_mysqlshell=*) SHELL_REPO="$val" ;;
            --mysqlshell_branch=*) SHELL_BRANCH="$val" ;;
            --protobuf_branch=*) PROTOBUF_BRANCH="$val" ;;
            --rpm_release=*) RPM_RELEASE="$val" ;;
            --deb_release=*) DEB_RELEASE="$val" ;;
            --help) usage ;;
            *)
                if test -n "$pick_args"
                then
                    append_arg_to_args "$arg"
                fi
            ;;
        esac
    done
}
check_workdir(){
    if [ "x$WORKDIR" = "x$CURDIR" ]
    then
        echo >&2 "Current directory cannot be used for building!"
        exit 1
    else
        if ! test -d "$WORKDIR"
        then
            echo >&2 "$WORKDIR is not a directory."
            exit 1
        fi
    fi
    return
}
add_percona_yum_repo(){
    if [ ! -f /etc/yum.repos.d/percona-dev.repo ]
    then
        cat >/etc/yum.repos.d/percona-dev.repo <<EOL
[percona-dev-$basearch]
name=Percona internal YUM repository for build slaves \$releasever - \$basearch
baseurl=http://jenkins.percona.com/yum-repo/\$releasever/RPMS/\$basearch
gpgkey=http://jenkins.percona.com/yum-repo/PERCONA-PACKAGING-KEY
gpgcheck=0
enabled=1

[percona-dev-noarch]
name=Percona internal YUM repository for build slaves \$releasever - noarch
baseurl=http://jenkins.percona.com/yum-repo/\$releasever/RPMS/noarch
gpgkey=http://jenkins.percona.com/yum-repo/PERCONA-PACKAGING-KEY
gpgcheck=0
enabled=1
EOL
    fi
    return
}
add_percona_apt_repo(){
    if [ ! -f /etc/apt/sources.list.d/percona-dev.list ]; then
        cat >/etc/apt/sources.list.d/percona-dev.list <<EOL
deb http://jenkins.percona.com/apt-repo/ @@DIST@@ main
deb-src http://jenkins.percona.com/apt-repo/ @@DIST@@ main
EOL
        sed -i "s:@@DIST@@:$OS_NAME:g" /etc/apt/sources.list.d/percona-dev.list
    fi
    add_key="apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys 9334A25F8507EFA5"
    until ${add_key}; do
        sleep 1
        echo "waiting"
    done
    return
}
get_porotobuf(){
    MY_PATH=$(echo $PATH)
    if [ "x$OS" = "xrpm" ]; then
        source /opt/rh/devtoolset-7/enable
    fi
    cd "${WORKDIR}"
    git clone "${PROTOBUF_REPO}"
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
    fi
    cd protobuf
    git clean -fd
    git reset --hard
    git checkout "$PROTOBUF_BRANCH"
    if [ "$PROTOBUF_BRANCH" = "v2.6.1" ]; then
        sed -i 's;curl http://googletest.googlecode.com/files/gtest-1.5.0.tar.bz2 | tar jx;curl -L https://github.com/google/googletest/archive/release-1.5.0.tar.gz | tar zx;' autogen.sh
        sed -i 's;mv gtest-1.5.0 gtest;mv googletest-release-1.5.0 gtest;' autogen.sh
    fi
    bash -x autogen.sh
    bash -x configure --disable-shared
    make
    mv src/.libs src/lib
    export PATH=$MY_PATH
    return
}
get_database(){
    MY_PATH=$(echo $PATH)
    if [ "x$OS" = "xrpm" ]; then
        source /opt/rh/devtoolset-7/enable
    fi
    cd "${WORKDIR}"
    git clone "${REPO}"
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
    fi
    repo_name=$(echo $REPO | awk -F'/' '{print $NF}' | awk -F'.' '{print $1}')
    cd $repo_name
    git clean -fd
    git reset --hard
    git checkout "$BRANCH"
    if [ $repo_name = "percona-server" ]; then
        git submodule init
        git submodule update
        patch -p0 < build-ps/rpm/mysql-5.7-sharedlib-rename.patch
    fi
    mkdir bld
    cd bld
    cmake .. -DDOWNLOAD_BOOST=1 -DENABLE_DOWNLOADS=1 -DWITH_SSL=system -DWITH_BOOST=$WORKDIR/boost
    cmake --build . --target mysqlclient
    cmake --build . --target mysqlxclient
    cd $WORKDIR
    export PATH=$MY_PATH
    return
}

get_v8(){
    #it should be built with gcc-4.X
    cd "${WORKDIR}"
    if [ "x$OS" = "xdeb" ]; then
        export CC=/usr/bin/gcc-4.8
        export CXX=/usr/bin/g++-4.8
    fi
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games
    export PATH=$(pwd)/depot_tools:$PATH
    export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
    git clone https://github.com/v8/v8.git
    cd v8/
    git checkout 3.28.71.19
    sed -i 's|dependencies: builddeps|dependencies:|' Makefile
    cd build
    git clone https://chromium.googlesource.com/experimental/external/gyp
    cd gyp/
    git checkout a3e2a5caf24a1e0a45401e09ad131210bf16b852
    cd ../../
    cd third_party
    git clone https://chromium.googlesource.com/chromium/deps/icu
    cd icu/
    git checkout 26d8859357ac0bfb86b939bf21c087b8eae22494
    cd ../../testing
    cp -r $WORKDIR/percona-server/source_downloads/googletest-release-1.8.0/googletest .
    cp -r $WORKDIR/percona-server/source_downloads/googletest-release-1.8.0/googlemock .
    mv googletest gtest
    mv googlemock gmock
    cd ../
    for file in $(grep -r fPIC * | awk -F':' '{print $1}' | sort | uniq); do 
        sed -i 's/-fPIC//g' $file
    done
    make dependencies
    
    make v8_static_library=true i18nsupport=off -j4 x64.release
    cd "${WORKDIR}"
    if [ "x$OS" = "xdeb" ]; then
	export CC=/usr/bin/gcc
        export CXX=/usr/bin/g++
    fi
}

get_sources(){
    #(better to execute on ubuntu)
    cd "${WORKDIR}"
    if [ "${SOURCE}" = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi
    git clone "$SHELL_REPO"
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi
    REVISION=$(git rev-parse --short HEAD)
    cd mysql-shell
    if [ ! -z "$SHELL_BRANCH" ]
    then
        git reset --hard
        git clean -xdf
        git checkout "$SHELL_BRANCH"
    fi
    if [ -z "${DESTINATION:-}" ]; then
        export DESTINATION=experimental
    fi
    echo "DESTINATION=${DESTINATION}" >> ../mysql-shell-8.0.properties
    echo "UPLOAD=UPLOAD/${DESTINATION}/BUILDS/myswl-shell/mysql-shell-80/${SHELL_BRANCH}/${REVISION}" >> ../mysql-shell-8.0.properties
    if [ "x$OS" = "xdeb" ]; then
        cd packaging/debian/
        cmake .
        cd ../../
        cmake . -DBUILD_SOURCE_PACKAGE=1 -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=RelWithDebInfo
        sed -i 's/-src//g' CPack*
    fi
    cpack -G TGZ --config CPackSourceConfig.cmake
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp mysql-shell*.tar.gz $WORKDIR/source_tarball
    cp mysql-shell*.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    rm -rf mysql-shell
    return
}
get_system(){
    if [ -f /etc/redhat-release ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        OS_NAME="el$RHEL"
        OS="rpm"
    else
        ARCH=$(uname -m)
        OS_NAME="$(lsb_release -sc)"
        OS="deb"
    fi
    return
}
install_deps() {
    if [ $INSTALL = 0 ]
    then
        echo "Dependencies will not be installed"
        return;
    fi
    if [ ! $( id -u ) -eq 0 ]
    then
        echo "It is not possible to instal dependencies. Please run as root"
        exit 1
    fi
    CURPLACE=$(pwd)
    if [ "x$OS" = "xrpm" ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        add_percona_yum_repo
        yum -y install http://www.percona.com/downloads/percona-release/redhat/0.1-4/percona-release-0.1-4.noarch.rpm || true
        yum -y install epel-release
        yum -y install git numactl-devel rpm-build gcc-c++ gperf ncurses-devel perl readline-devel openssl-devel jemalloc 
        yum -y install time zlib-devel libaio-devel bison cmake pam-devel libeatmydata jemalloc-devel
        yum -y install perl-Time-HiRes libcurl-devel openldap-devel unzip wget libcurl-devel
        yum -y install perl-Env perl-Data-Dumper perl-JSON MySQL-python perl-Digest perl-Digest-MD5 perl-Digest-Perl-MD5 || true
        yum -y install automake m4 libtool protobuf protobuf-devel protobuf-static
        until yum -y install centos-release-scl; do
            echo "waiting"
            sleep 1
        done
        yum -y install  gcc-c++ devtoolset-7-gcc-c++ devtoolset-7-binutils
        if [ "x$RHEL" = "x6" ]; then
            yum -y install Percona-Server-shared-56
        fi
    else
        apt-get -y install dirmngr || true
        add_percona_apt_repo
        apt-get update
        apt-get -y install dirmngr || true
        apt-get -y install lsb-release wget
        export DEBIAN_FRONTEND="noninteractive"
        export DIST="$(lsb_release -sc)"
        until sudo apt-get update; do
            sleep 1
            echo "waiting"
        done
        apt-get -y purge eatmydata || true
        echo "deb http://jenkins.percona.com/apt-repo/ ${DIST} main" > percona-dev.list
        mv -f percona-dev.list /etc/apt/sources.list.d/
        wget -q -O - http://jenkins.percona.com/apt-repo/8507EFA5.pub | sudo apt-key add -
        wget -q -O - http://jenkins.percona.com/apt-repo/CD2EFD2A.pub | sudo apt-key add -
        apt-get update
        apt-get -y install psmisc
        apt-get -y install libsasl2-modules:amd64 || apt-get -y install libsasl2-modules
        apt-get -y install dh-systemd || true
        apt-get -y install curl bison cmake perl libssl-dev gcc g++ libaio-dev libldap2-dev libwrap0-dev gdb unzip gawk
        apt-get -y install lsb-release libmecab-dev libncurses5-dev libreadline-dev libpam-dev zlib1g-dev libcurl4-openssl-dev
        apt-get -y install libldap2-dev libnuma-dev libjemalloc-dev libeatmydata libc6-dbg valgrind libjson-perl python-mysqldb libsasl2-dev
        apt-get -y install libmecab2 mecab mecab-ipadic libicu-devel
        apt-get -y install build-essential devscripts doxygen doxygen-gui graphviz rsync libprotobuf-dev protobuf-compiler
        apt-get -y install cmake autotools-dev autoconf automake build-essential devscripts debconf debhelper fakeroot libicu-dev libtool gcc-4.8 g++-4.8 python python-dev zip
    fi
    if [ ! -d /usr/local/percona-subunit2junitxml ]; then
        cd /usr/local
        git clone https://github.com/percona/percona-subunit2junitxml.git
        rm -rf /usr/bin/subunit2junitxml
        ln -s /usr/local/percona-subunit2junitxml/subunit2junitxml /usr/bin/subunit2junitxml
        cd ${CURPLACE}
    fi
    return;
}
get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'mysql-shell*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'mysql-shell*.tar.gz' | sort | tail -n1))
        if [ -z $TARFILE ]
        then
            echo "There is no $TARBALL for build"
            exit 1
        else
            cp $CURDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
        fi
    else
        cp $WORKDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
    fi
    return
}
get_deb_sources(){
    param=$1
    echo $param
    FILE=$(basename $(find $WORKDIR/source_deb -name "mysql-shell*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -name "mysql-shell*.$param" | sort | tail -n1))
        if [ -z $FILE ]
        then
            echo "There is no sources for build"
            exit 1
        else
            cp $CURDIR/source_deb/$FILE $WORKDIR/
        fi
    else
        cp $WORKDIR/source_deb/$FILE $WORKDIR/
    fi
    return
}

build_srpm(){
    MY_PATH=$(echo $PATH)
    if [ $SRPM = 0 ]
    then
        echo "SRC RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build src rpm here"
        exit 1
    fi
    source /opt/rh/devtoolset-7/enable
    cd $WORKDIR
    get_tar "source_tarball"
    rm -fr rpmbuild
    ls | grep -v mysql-shell*.tar.* | xargs rm -rf
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    TARFILE=$(basename $(find . -name 'mysql-shell-*.tar.gz' | sort | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2}')
    VERSION=$(echo ${TARFILE}| awk -F '-' '{print $3}')
    #
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    TMPREL=$(echo ${TARFILE}| awk -F '-' '{print $4}')
    RELEASE=${TMPREL%.tar.gz}
    #
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    #
    cd ${WORKDIR}/rpmbuild/SPECS
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/packaging/rpm/*.spec.in' --strip=3
    mv mysql-shell.spec.in mysql-shell.spec
    #
    sed -i 's/@COMMERCIAL_VER@/0/g' mysql-shell.spec
    sed -i 's/@PRODUCT_SUFFIX@//g' mysql-shell.spec
    sed -i 's/@MYSH_NO_DASH_VERSION@/8.0.12/g' mysql-shell.spec
    sed -i "s:@RPM_RELEASE@:${RPM_RELEASE}:g" mysql-shell.spec
    sed -i 's/@LICENSE_TYPE@/GPLv2/g' mysql-shell.spec
    sed -i 's/@PRODUCT@/MySQL Shell/' mysql-shell.spec
    sed -i 's/@MYSH_VERSION@/8.0.12/g' mysql-shell.spec
    sed -i "s:-DHAVE_PYTHON=1 \ : -DHAVE_PYTHON=1 -DWITH_STATIC_LINKING=ON -DMYSQL_EXTRA_LIBRARIES='-lz -ldl -lssl -lcrypto -licui18n -licuuc -licudata' :" mysql-shell.spec
    #sed -i "s:-DV8_INCLUDE_DIR=%{v8_includedir} ::g" mysql-shell.spec
    #sed -i "s:-DV8_LIB_DIR=%{v8_libdir} ::g" mysql-shell.spec
    cd ${WORKDIR}
    #
    mv -fv ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES
    #
    rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .generic" rpmbuild/SPECS/mysql-shell.spec
    #
    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${WORKDIR}/srpm
    export PATH=$MY_PATH
    return
}
build_rpm(){
    MY_PATH=$(echo $PATH)
    if [ $RPM = 0 ]
    then
        echo "RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build rpm here"
    fi
    SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'mysql-shell-*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'mysql-shell-*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]
        then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
        else
            cp $CURDIR/srpm/$SRC_RPM $WORKDIR
        fi
    else
        cp $WORKDIR/srpm/$SRC_RPM $WORKDIR
    fi
    cd $WORKDIR
    rm -fr rpmbuild
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    cp $SRC_RPM rpmbuild/SRPMS/
    RHEL=$(rpm --eval %rhel)
    ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    #
    echo "RHEL=${RHEL}" >> percona-server-8.0.properties
    echo "ARCH=${ARCH}" >> percona-server-8.0.properties
    #
    SRCRPM=$(basename $(find . -name '*.src.rpm' | sort | tail -n1))
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    #
    mv *.src.rpm rpmbuild/SRPMS
    get_porotobuf
    get_database
    get_v8
    source /opt/rh/devtoolset-7/enable
    cd ${WORKDIR}
    #
    rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .el${RHEL}" --define "with_mysql_source $WORKDIR/percona-server" --define "static 1" --define "with_protobuf $WORKDIR/protobuf" --define "v8_includedir $WORKDIR/v8/include" --define "v8_libdir $WORKDIR/v8/out/x64.release/obj.target/tools/gyp" --rebuild rpmbuild/SRPMS/${SRCRPM}
    return_code=$?
    if [ $return_code != 0 ]; then
        exit $return_code
    fi
    mkdir -p ${WORKDIR}/rpm
    mkdir -p ${CURDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${WORKDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${CURDIR}/rpm
    export PATH=$MY_PATH
}
build_source_deb(){
    if [ $SDEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrpm" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    rm -rf percona-server*
    get_tar "source_tarball"
    rm -f *.dsc *.orig.tar.gz *.debian.tar.gz *.changes
    #
    TARFILE=$(basename $(find . -name 'mysql-shell-*.tar.gz' | grep -v tokudb | sort | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2}')
    VERSION=$(echo ${TARFILE}| awk -F '-' '{print $3}' | awk -F '.tar' '{print $1}')
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    TMPREL=$(echo ${TARFILE}| awk -F '-' '{print $4}')
    RELEASE=1
    NEWTAR=${NAME}_${VERSION}.orig.tar.gz
    mv ${TARFILE} ${NEWTAR}
    tar xzf ${NEWTAR}
    cd ${NAME}-${VERSION}
    dch -D unstable --force-distribution -v "${VERSION}-${DEB_RELEASE}" "Update to new upstream release mysql-shell ${VERSION}-1"
    dpkg-buildpackage -S
    cd ${WORKDIR}
    mkdir -p $WORKDIR/source_deb
    mkdir -p $CURDIR/source_deb
    cp *.debian.tar.* $WORKDIR/source_deb
    cp *_source.changes $WORKDIR/source_deb
    cp *.dsc $WORKDIR/source_deb
    cp *.orig.tar.gz $WORKDIR/source_deb
    cp *.debian.tar.* $CURDIR/source_deb
    cp *_source.changes $CURDIR/source_deb
    cp *.dsc $CURDIR/source_deb
    cp *.orig.tar.gz $CURDIR/source_deb
}

build_deb(){
    if [ $DEB = 0 ]
    then
        echo "Deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrpm" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    for file in 'dsc' 'orig.tar.gz' 'changes' 'debian.tar*'
    do
        get_deb_sources $file
    done
    cd $WORKDIR
    rm -fv *.deb
    export DEBIAN_VERSION="$(lsb_release -sc)"
    DSC=$(basename $(find . -name '*.dsc' | sort | tail -n 1))
    DIRNAME=$(echo ${DSC%-${DEB_RELEASE}.dsc} | sed -e 's:_:-:g')
    VERSION=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $4}')
    RELEASE=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $5}')
    ARCH=$(uname -m)
    export EXTRAVER=${MYSQL_VERSION_EXTRA#-}
    #
    echo "ARCH=${ARCH}" >> percona-server-8.0.properties
    echo "DEBIAN_VERSION=${DEBIAN_VERSION}" >> percona-server-8.0.properties
    echo "VERSION=${VERSION}" >> percona-server-8.0.properties
    #
    dpkg-source -x ${DSC}
    get_porotobuf
    get_database
    get_v8
    cd mysql-shell-$SHELL_BRANCH
    sed -i 's/make -j8/make -j8\n\t/' debian/rules
    sed -i '/-DCMAKE/,/j8/d' debian/rules
    cp debian/mysql-shell.install debian/install
    sed -i 's:-rm -fr debian/tmp/usr/lib*/*.{so*,a} 2>/dev/null:-rm -fr debian/tmp/usr/lib*/*.{so*,a} 2>/dev/null\n\tmv debian/tmp/usr/local/* debian/tmp/usr/\n\trm -rf debian/tmp/usr/local:' debian/rules
    sed -i "s:VERBOSE=1:-DCMAKE_BUILD_TYPE=RelWithDebInfo -DEXTRA_INSTALL=\"\" -DEXTRA_NAME_SUFFIX=\"\" -DMYSQL_SOURCE_DIR=${WORKDIR}/percona-server -DMYSQL_BUILD_DIR=${WORKDIR}/percona-server/bld -DMYSQL_EXTRA_LIBRARIES=\"-lz -ldl -lssl -lcrypto -licui18n -licuuc -licudata \" -DWITH_PROTOBUF=${WORKDIR}/protobuf/src -DV8_INCLUDE_DIR=${WORKDIR}/v8/include -DV8_LIB_DIR=${WORKDIR}/v8/out/x64.release/obj.target/tools/gyp -DHAVE_PYTHON=1 -DWITH_STATIC_LINKING=ON . \n\t DEB_BUILD_HARDENING=1 make -j8 VERBOSE=1:" debian/rules

    dch -b -m -D "$DEBIAN_VERSION" --force-distribution -v "${VERSION}-${DEB_RELEASE}.${DEBIAN_VERSION}" 'Update distribution'
    dpkg-buildpackage -rfakeroot -uc -us -b
    cd ${WORKDIR}
    mkdir -p $CURDIR/deb
    mkdir -p $WORKDIR/deb
    cp $WORKDIR/*.deb $WORKDIR/deb
    cp $WORKDIR/*.deb $CURDIR/deb
}
build_tarball(){
    if [ $TARBALL = 0 ]
    then
        echo "Binary tarball will not be created"
        return;
    fi
    get_tar "source_tarball"
    cd $WORKDIR
    TARFILE=$(basename $(find . -name 'percona-server-*.tar.gz' | sort | tail -n1))
    if [ -f /etc/debian_version ]; then
        export OS_RELEASE="$(lsb_release -sc)"
    fi
    #
    if [ -f /etc/redhat-release ]; then
        export OS_RELEASE="centos$(lsb_release -sr | awk -F'.' '{print $1}')"
        RHEL=$(rpm --eval %rhel)
        source /opt/rh/devtoolset-7/enable
    fi
    #
    ARCH=$(uname -m 2>/dev/null||true)
    TARFILE=$(basename $(find . -name 'percona-server-*.tar.gz' | sort | grep -v "tools" | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2}')
    VERSION=$(echo ${TARFILE}| awk -F '-' '{print $3}')
    #
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    TMPREL=$(echo ${TARFILE}| awk -F '-' '{print $4}')
    RELEASE=${TMPREL%.tar.gz}
    #
    export CFLAGS=$(rpm --eval %{optflags} | sed -e "s|march=i386|march=i686|g")
    export CXXFLAGS="${CFLAGS}"
    if [ "${YASSL}" = 0 ]; then
        if [ -f /etc/redhat-release ]; then
            SSL_VER_TMP=$(yum list installed|grep -i openssl|head -n1|awk '{print $2}'|awk -F "-" '{print $1}'|sed 's/\.//g'|sed 's/[a-z]$//')
            export SSL_VER=".ssl${SSL_VER_TMP}"
        else
            SSL_VER_TMP=$(dpkg -l|grep -i libssl|grep -v "libssl\-"|head -n1|awk '{print $2}'|awk -F ":" '{print $1}'|sed 's/libssl/ssl/g'|sed 's/\.//g')
            export SSL_VER=".${SSL_VER_TMP}"
        fi
    fi
    build_mecab_lib
    build_mecab_dict
    MECAB_INSTALL_DIR="${WORKDIR}/mecab-install"
    rm -fr TARGET && mkdir TARGET
    rm -rf jemalloc
    git clone https://github.com/jemalloc/jemalloc
    (
    cd jemalloc
    git checkout 3.6.0
    bash autogen.sh
    )
    #
    rm -fr ${TARFILE%.tar.gz}
    tar xzf ${TARFILE}
    cd ${TARFILE%.tar.gz}
    if [ "${YASSL}" = 1 ]; then
        DIRNAME="tarball_yassl"
        CMAKE_OPTS="-DWITH_ROCKSDB=1" bash -xe ./build-ps/build-binary.sh --with-jemalloc=../jemalloc/ --with-yassl --with-mecab="${MECAB_INSTALL_DIR}/usr" ../TARGET
    else
        CMAKE_OPTS="-DWITH_ROCKSDB=1" bash -xe ./build-ps/build-binary.sh --with-mecab="${MECAB_INSTALL_DIR}/usr" --with-jemalloc=../jemalloc/ ../TARGET
        DIRNAME="tarball"
    fi
    mkdir -p ${WORKDIR}/${DIRNAME}
    mkdir -p ${CURDIR}/${DIRNAME}
    cp ../TARGET/*.tar.gz ${WORKDIR}/${DIRNAME}
    cp ../TARGET/*.tar.gz ${CURDIR}/${DIRNAME}
}
#main
CURDIR=$(pwd)
VERSION_FILE=$CURDIR/percona-server-8.0.properties
args=
WORKDIR=
SRPM=0
SDEB=0
RPM=0
DEB=0
SOURCE=0
TARBALL=0
OS_NAME=
ARCH=
OS=
PROTOBUF_REPO="https://github.com/protocolbuffers/protobuf.git"
SHELL_REPO="https://github.com/mysql/mysql-shell.git"
SHELL_BRANCH="8.0"
PROTOBUF_BRANCH=v2.6.1
INSTALL=0
RPM_RELEASE=1
DEB_RELEASE=1
REVISION=0
BRANCH="8.0"
RPM_RELEASE=1
DEB_RELEASE=1
YASSL=0
REPO="https://github.com/percona/percona-server.git"
MYSQL_VERSION_EXTRA=-1
parse_arguments PICK-ARGS-FROM-ARGV "$@"
if [ ${YASSL} = 1 ]; then
    TARBALL=1
fi
check_workdir
get_system
install_deps
get_sources
build_tarball
build_srpm
build_source_deb
build_rpm
build_deb
