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
    wget -qO - http://jenkins.percona.com/apt-repo/8507EFA5.pub | apt-key add -
    return
}
get_protobuf(){
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
    if [ "x$OS" = "xrpm" ]; then
        source /opt/rh/devtoolset-7/enable
    fi
    bash -x autogen.sh
    bash -x configure --disable-shared
    make
    make install
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
        if [ "x$OS_NAME" = "xstretch" ]; then
            export CC=/usr/bin/gcc-4.9
            export CXX=/usr/bin/g++-4.9
        else
            export CC=/usr/bin/gcc-4.8
            export CXX=/usr/bin/g++-4.8
        fi
    else
        if [ "x$RHEL" = "x6" ]; then
            source /opt/percona-devtoolset/enable
        else
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games
        fi
    fi
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
    export PATH=$(pwd)/depot_tools:$PATH
    export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
    git clone https://chromium.googlesource.com/experimental/external/v8
    cd v8/
    git checkout 31c0e32e19ad3df48525fa9e7b2d1c0c07496d00
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
    if [ "x$OS" = "xrpm" ]; then
        if [ "x$RHEL" = "x6" ]; then
            export CXXFLAGS='-Wno-unused-function -Wno-expansion-to-defined -Wno-strict-overflow'
        fi
    fi
    if [ "x$OS" = "xdeb" ]; then
        if [ "x$OS_NAME" != 'xxenial' ]; then
            export CXXFLAGS='-fPIC -Wno-unused-function -Wno-expansion-to-defined -Wno-strict-overflow'
        fi
    fi
    #export CXXFLAGS='-fPIC -Wno-unused-function -Wno-expansion-to-defined -Wno-strict-overflow'
    make dependencies

    make v8_static_library=true i18nsupport=off x64.release
    retval=$?
    if [ $retval != 0 ]
    then
        exit 1
    fi
    cd "${WORKDIR}"
    if [ "x$OS" = "xdeb" ]; then
        export CC=/usr/bin/gcc
        export CXX=/usr/bin/g++
    else
        source /opt/rh/devtoolset-7/enable
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
    if [ "x$OS" = "xrpm" ]; then
        source /opt/rh/devtoolset-7/enable
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
    echo "REVISION=${REVISION}" >> ../mysql-shell.properties
    BRANCH_NAME="${BRANCH}"
    echo "BRANCH_NAME=${BRANCH_NAME}" >> ../mysql-shell.properties
    export PRODUCT='mysql-shell'
    echo "PRODUCT=mysql-shell" >> ../mysql-shell.properties
    echo "SHELL_BRANCH=${SHELL_BRANCH}" >> ../mysql-shell.properties
    echo "RPM_RELEASE=${RPM_RELEASE}" >> ../mysql-shell.properties
    echo "DEB_RELEASE=${DEB_RELEASE}" >> ../mysql-shell.properties

    echo "DESTINATION=${DESTINATION}" >> ../mysql-shell.properties
    TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
    echo "UPLOAD=UPLOAD/${DESTINATION}/BUILDS/mysql-shell/mysql-shell-80/${SHELL_BRANCH}/${TIMESTAMP}" >> ../mysql-shell.properties
    if [ "x$OS" = "xdeb" ]; then
        cd packaging/debian/
        cmake .
        cd ../../
        cmake . -DBUILD_SOURCE_PACKAGE=1 -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=RelWithDebInfo
    else
        cmake . -DBUILD_SOURCE_PACKAGE=1 -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=RelWithDebInfo
    fi
    sed -i 's/-src//g' CPack*
    cpack -G TGZ --config CPackSourceConfig.cmake
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    TAR_NAME=$(ls mysql-shell*.tar.gz)
    cp mysql-shell*.tar.gz $WORKDIR/source_tarball/percona-${TAR_NAME}
    cp mysql-shell*.tar.gz $CURDIR/source_tarball/percona-${TAR_NAME}
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
        yum -y install libicu-devel automake m4 libtool python-devel zip rpmlint
        until yum -y install centos-release-scl; do
            echo "waiting"
            sleep 1
        done
        yum -y install  gcc-c++ devtoolset-7-gcc-c++ devtoolset-7-binutils
        if [ "x$RHEL" = "x6" ]; then
            yum -y install Percona-Server-shared-56
            yum install -y percona-devtoolset-gcc percona-devtoolset-binutils python-devel percona-devtoolset-gcc-c++ percona-devtoolset-libstdc++-devel percona-devtoolset-valgrind-devel
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
        apt-get -y install cmake autotools-dev autoconf automake build-essential devscripts debconf debhelper fakeroot libicu-dev libtool
        if [ "x$OS_NAME" = "xstretch" ]; then
            echo "deb http://ftp.us.debian.org/debian/ jessie main contrib non-free" >> /etc/apt/sources.list
            apt-get update
            apt-get -y install gcc-4.9 g++-4.9
            sed -i 's;deb http://ftp.us.debian.org/debian/ jessie main contrib non-free;;' /etc/apt/sources.list
            apt-get update
        else
            apt-get -y install gcc-4.8 g++-4.8
        fi
        apt-get -y install python python-dev zip
        apt-get -y install python27-dev
    fi
    if [ ! -d /usr/local/percona-subunit2junitxml ]; then
        cd /usr/local
        git clone https://github.com/percona/percona-subunit2junitxml.git
        rm -rf /usr/bin/subunit2junitxml
        ln -s /usr/local/percona-subunit2junitxml/subunit2junitxml /usr/bin/subunit2junitxml
        cd ${CURPLACE}
    fi
    get_protobuf
    return;
}
get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'percona-mysql-shell*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'percona-mysql-shell*.tar.gz' | sort | tail -n1))
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
    FILE=$(basename $(find $WORKDIR/source_deb -name "percona-mysql-shell*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -name "percona-mysql-shell*.$param" | sort | tail -n1))
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
    ls | grep -v percona-mysql-shell*.tar.* | grep -v protobuf | xargs rm -rf
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    TARFILE=$(basename $(find . -name 'percona-mysql-shell-*.tar.gz' | sort | tail -n1))
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
    sed -i 's|mysql-shell@PRODUCT_SUFFIX@|percona-mysql-shell@PRODUCT_SUFFIX@|' mysql-shell.spec
    sed -i 's|https://cdn.mysql.com/Downloads/%{name}-@MYSH_VERSION@-src.tar.gz|%{name}-@MYSH_VERSION@.tar.gz|' mysql-shell.spec
    sed -i 's|%{name}-@MYSH_VERSION@-src|%{name}-@MYSH_VERSION@|' mysql-shell.spec
    sed -i 's|%setup -q -n %{name}-|%setup -q -n mysql-shell-|' mysql-shell.spec
    sed -i '/with_protobuf/,/endif/d' mysql-shell.spec
    sed -i 's/@COMMERCIAL_VER@/0/g' mysql-shell.spec
    sed -i 's/@PRODUCT_SUFFIX@//g' mysql-shell.spec
    sed -i 's/@MYSH_NO_DASH_VERSION@/8.0.13/g' mysql-shell.spec
    sed -i "s:@RPM_RELEASE@:${RPM_RELEASE}:g" mysql-shell.spec
    sed -i 's/@LICENSE_TYPE@/GPLv2/g' mysql-shell.spec
    sed -i 's/@PRODUCT@/MySQL Shell/' mysql-shell.spec
    sed -i 's/@MYSH_VERSION@/8.0.13/g' mysql-shell.spec
    sed -i "s:-DHAVE_PYTHON=1 \ : -DHAVE_PYTHON=1 -DWITH_STATIC_LINKING=ON -DMYSQL_EXTRA_LIBRARIES='-lz -ldl -lssl -lcrypto -licui18n -licuuc -licudata' :" mysql-shell.spec
    mv mysql-shell.spec percona-mysql-shell.spec
    cd ${WORKDIR}
    #
    mv -fv ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES
    #
    rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .generic" rpmbuild/SPECS/percona-mysql-shell.spec
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
    SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'percona-mysql-shell-*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'percona-mysql-shell-*.src.rpm' | sort | tail -n1))
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
    echo "RHEL=${RHEL}" >> mysql-shell.properties
    echo "ARCH=${ARCH}" >> mysql-shell.properties
    #
    SRCRPM=$(basename $(find . -name '*.src.rpm' | sort | tail -n1))
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    #
    mv *.src.rpm rpmbuild/SRPMS
    get_database
    get_v8
    source /opt/rh/devtoolset-7/enable
    cd ${WORKDIR}
    #
    rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .el${RHEL}" --define "with_mysql_source $WORKDIR/percona-server" --define "static 1" --define "with_protobuf $WORKDIR/protobuf/src/" --define "v8_includedir $WORKDIR/v8/include" --define "v8_libdir $WORKDIR/v8/out/x64.release/obj.target/tools/gyp" --rebuild rpmbuild/SRPMS/${SRCRPM}
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
    rm -rf mysql-shell*
    get_tar "source_tarball"
    rm -f *.dsc *.orig.tar.gz *.debian.tar.* *.changes
    #
    TARFILE=$(basename $(find . -name 'percona-mysql-shell-*.tar.gz' | grep -v tokudb | sort | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2"-"$3}')
    VERSION=$(echo ${TARFILE}| awk -F '-' '{print $4}' | awk -F '.tar' '{print $1}')
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    TMPREL="1.tar.gz"
    RELEASE=1
    NEWTAR=${NAME}_${VERSION}-${RELEASE}.orig.tar.gz
    mv ${TARFILE} ${NEWTAR}
    tar xzf ${NEWTAR}
    cd mysql-shell-${VERSION}
    sed -i 's|Source: mysql-shell|Source: percona-mysql-shell|' debian/control
    sed -i 's|Package: mysql-shell|Package: percona-mysql-shell|' debian/control
    sed -i 's|mysql-shell|percona-mysql-shell|' debian/changelog
    dch -D unstable --force-distribution -v "${VERSION}-${RELEASE}-${DEB_RELEASE}" "Update to new upstream release ${VERSION}-${RELEASE}-1"
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
	ls $WORKDIR */*
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
    echo "ARCH=${ARCH}" >> mysql-shell.properties
    echo "DEBIAN_VERSION=${DEBIAN_VERSION}" >> mysql-shell.properties
    echo "VERSION=${VERSION}" >> mysql-shell.properties
    #
    dpkg-source -x ${DSC}
    #get_protobuf
    get_database
    get_v8
    cd percona-mysql-shell-$SHELL_BRANCH-1
    sed -i 's/make -j8/make -j8\n\t/' debian/rules
    sed -i '/-DCMAKE/,/j8/d' debian/rules
    cp debian/mysql-shell.install debian/install
    sed -i 's:-rm -fr debian/tmp/usr/lib*/*.{so*,a} 2>/dev/null:-rm -fr debian/tmp/usr/lib*/*.{so*,a} 2>/dev/null\n\tmv debian/tmp/usr/local/* debian/tmp/usr/\n\trm -rf debian/tmp/usr/local:' debian/rules
    sed -i "s:VERBOSE=1:-DCMAKE_BUILD_TYPE=RelWithDebInfo -DEXTRA_INSTALL=\"\" -DEXTRA_NAME_SUFFIX=\"\" -DMYSQL_SOURCE_DIR=${WORKDIR}/percona-server -DMYSQL_BUILD_DIR=${WORKDIR}/percona-server/bld -DMYSQL_EXTRA_LIBRARIES=\"-lz -ldl -lssl -lcrypto -licui18n -licuuc -licudata \" -DWITH_PROTOBUF=${WORKDIR}/protobuf/src -DV8_INCLUDE_DIR=${WORKDIR}/v8/include -DV8_LIB_DIR=${WORKDIR}/v8/out/x64.release/obj.target/tools/gyp -DHAVE_PYTHON=1 -DWITH_STATIC_LINKING=ON . \n\t DEB_BUILD_HARDENING=1 make -j8 VERBOSE=1:" debian/rules
    sed -i 's:} 2>/dev/null:} 2>/dev/null\n\tmv debian/tmp/usr/local/* debian/tmp/usr/\n\trm -fr debian/tmp/usr/local:' debian/rules
    sed -i 's:, libprotobuf-dev, protobuf-compiler::' debian/control

    dch -b -m -D "$DEBIAN_VERSION" --force-distribution -v "${VERSION}-${RELEASE}-${DEB_RELEASE}.${DEBIAN_VERSION}" 'Update distribution'
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
    TARFILE=$(basename $(find . -name 'percona-mysql-shell*.tar.gz' | sort | tail -n1))
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
    TARFILE=$(basename $(find . -name 'percona-mysql-shell*.tar.gz' | sort | grep -v "tools" | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2"-"$3}')
    VERSION=$(echo ${TARFILE}| awk -F '-' '{print $4}' | awk -F '.tar' '{print $1}')
    VER=$(echo ${TARFILE}| awk -F '-' '{print $4}' | awk -F'.' '{print $1}')
    #
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    TMPREL=$(echo ${TARFILE}| awk -F '-' '{print $5}')
    RELEASE=${TMPREL%.tar.gz}
    #
    get_database
    get_v8
    cd ${WORKDIR}
    rm -fr ${TARFILE%.tar.gz}
    tar xzf ${TARFILE}
    cd mysql-shell-${VERSION}
    DIRNAME="tarball"
    mkdir bld
    cd bld
    cmake .. -DMYSQL_SOURCE_DIR=${WORKDIR}/percona-server \
            -DMYSQL_BUILD_DIR=${WORKDIR}/percona-server/bld \
            -DMYSQL_EXTRA_LIBRARIES="-lz -ldl -lssl -lcrypto -licui18n -licuuc -licudata " \
            -DWITH_PROTOBUF=${WORKDIR}/protobuf/src \
            -DV8_INCLUDE_DIR=${WORKDIR}/v8/include \
            -DV8_LIB_DIR=${WORKDIR}/v8/out/x64.release/obj.target/tools/gyp \
            -DHAVE_PYTHON=1 \
            -DWITH_STATIC_LINKING=ON
    make -j4
    mkdir ${NAME}-${VERSION}-${OS_NAME}
    cp -r bin ${NAME}-${VERSION}-${OS_NAME}/
    cp -r share ${NAME}-${VERSION}-${OS_NAME}/
    tar -zcvf ${NAME}-${VERSION}-${OS_NAME}.tar.gz ${NAME}-${VERSION}-${OS_NAME}
    mkdir -p ${WORKDIR}/${DIRNAME}
    mkdir -p ${CURDIR}/${DIRNAME}
    cp *.tar.gz ${WORKDIR}/${DIRNAME}
    cp *.tar.gz ${CURDIR}/${DIRNAME}
}
#main
CURDIR=$(pwd)
VERSION_FILE=$CURDIR/mysql-shell.properties
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
