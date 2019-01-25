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
        --branch            Branch for build
        --repo              Repo for build
        --rpm_release       RPM version( default = 1)
        --deb_release       DEB version( default = 1)
        --help) usage ;;
Example $0 --builddir=/tmp/PXC57 --get_sources=1 --build_src_rpm=1 --build_rpm=1
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
            --branch=*) BRANCH="$val" ;;
            --repo=*) REPO="$val" ;;
            --install_deps=*) INSTALL="$val" ;;
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
        curl -o /etc/yum.repos.d/ https://jenkins.percona.com/yum-repo/percona-dev.repo
    fi
    return
}

add_percona_apt_repo(){
  if [ ! -f /etc/apt/sources.list.d/percona-dev.list ]; then
    curl -o /etc/apt/sources.list.d/ https://jenkins.percona.com/apt-repo/percona-dev.list.template
    mv /etc/apt/sources.list.d/percona-dev.list.template /etc/apt/sources.list.d/percona-dev.list
    sed -i "s:@@DIST@@:$OS_NAME:g" /etc/apt/sources.list.d/percona-dev.list
  fi
 
  wget -q -O - http://jenkins.percona.com/apt-repo/8507EFA5.pub | sudo apt-key add -
  wget -q -O - http://jenkins.percona.com/apt-repo/CD2EFD2A.pub | sudo apt-key add -
  return
}

get_sources(){
    cd "${WORKDIR}"
    if [ "${SOURCE}" = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi

    git clone "$REPO"
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi

    cd percona-xtradb-cluster
    if [ ! -z "$BRANCH" ]
    then
        git reset --hard
        git clean -xdf
        git checkout "$BRANCH"
    fi

    git submodule deinit -f .
    git submodule init
    git submodule update

    WSREP_VERSION="$(grep WSREP_INTERFACE_VERSION wsrep/src/wsrep_api.h | cut -d '"' -f2).$(grep 'SET(WSREP_PATCH_VERSION'  "cmake/wsrep.cmake" | cut -d '"' -f2)"
    WSREP_REV="$(test -r WSREP-REVISION && cat WSREP-REVISION)"
    REVISION=$(git rev-parse --short HEAD)
    GALERA_REVNO="$(test -r percona-xtradb-cluster-galera/GALERA-REVISION && cat percona-xtradb-cluster-galera/GALERA-REVISION)"
    source VERSION
    export MYSQL_VERSION="$MYSQL_VERSION_MAJOR.$MYSQL_VERSION_MINOR.$MYSQL_VERSION_PATCH"
    export MYSQL_RELEASE="$(echo $MYSQL_VERSION_EXTRA | sed 's/^-//')"

    PRODUCT=Percona-XtraDB-Cluster-57
    PRODUCT_FULL=Percona-XtraDB-Cluster-${MYSQL_VERSION}-${WSREP_VERSION}

    echo "WSREP_VERSION=${WSREP_VERSION}" > ${WORKDIR}/pxc-57.properties
    echo "WSREP_REV=${WSREP_REV}" >> ${WORKDIR}/pxc-57.properties
    echo "REVISION=${REVISION}" >> ${WORKDIR}/pxc-57.properties
    echo "MYSQL_VERSION=$MYSQL_VERSION" >> ${WORKDIR}/pxc-57.properties
    echo "MYSQL_RELEASE=$MYSQL_RELEASE" >> ${WORKDIR}/pxc-57.properties
    echo "BRANCH_NAME=${BRANCH}" >> ${WORKDIR}/pxc-57.properties
    echo "PRODUCT=${PRODUCT}" >> ${WORKDIR}/pxc-57.properties

    echo "PRODUCT_FULL=${PRODUCT_FULL}" >> ${WORKDIR}/pxc-57.properties
    echo "BUILD_NUMBER=${BUILD_NUMBER}" >> ${WORKDIR}/pxc-57.properties
    #
    if [ -z "${DESTINATION:-}" ]; then
    export DESTINATION=experimental
    fi 
    DESTINATION="UPLOAD/${DESTINATION}/BUILDS/${PRODUCT}/${PRODUCT_FULL}/${BRANCH}/${BUILD_NUMBER}/${REVISION}"
    echo "DESTINATION=UPLOAD/${DESTINATION}/BUILDS/${PRODUCT}/${PRODUCT_FULL}/${BRANCH}/${BUILD_NUMBER}/${REVISION}" >> ${WORKDIR}/pxc-57.properties
    echo "GALERA_REVNO=${GALERA_REVNO}" >>${WORKDIR}/pxc-57.properties
    DEST=${DESTINATION}
    echo "DEST=${DEST}" >> ${WORKDIR}/pxc-57.properties
    cmake . -DDOWNLOAD_BOOST=1 -DWITH_ROCKSDB=0 -DWITH_BOOST=build-ps/boost
    make dist
    mv *.tar.gz ${WORKDIR}/
    cd ${WORKDIR}
    cat pxc-57.properties
    cd ${WORKDIR}
    ls
    #EXPORTED_TAR=$(basename $(find . -type f -name "*.tar.gz" | sort  | grep -v new | tail -n 1))
    EXPORTED_TAR=$(ls | grep tar.gz )
    #
    PXCDIR=${EXPORTED_TAR%.tar.gz}
    rm -fr ${PXCDIR}
    tar xzf ${EXPORTED_TAR}
    rm -f ${EXPORTED_TAR}
    # add git submodules because make dist uses git archive which doesn't include them
    rsync -av ${WORKDIR}/percona-xtradb-cluster/percona-xtradb-cluster-galera/ ${PXCDIR}/percona-xtradb-cluster-galera --exclude .git

    #rsync -av ${WORKDIR}/percona-xtradb-cluster/wsrep ${PXCDIR}/percona-xtradb-cluster-galera/wsrep --exclude .git

    rsync -av ${WORKDIR}/percona-xtradb-cluster/wsrep/src/ ${PXCDIR}/percona-xtradb-cluster-galera/wsrep/src --exclude .git
    rsync -av ${WORKDIR}/percona-xtradb-cluster/wsrep/src/ ${PXCDIR}/wsrep/src --exclude .git


    #rsync -av ${WORKDIR}/percona-xtradb-cluster/proxysql/ ${PXCDIR}/proxysql --exclude .git
    cd ${WORKDIR}
    #
    tar --owner=0 --group=0 --exclude=.bzr --exclude=.git -czf ${PXCDIR}.tar.gz ${PXCDIR}
    rm -fr ${PXCDIR}
    cat pxc-57.properties

    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp ${PXCDIR}.tar.gz $WORKDIR/source_tarball
    cp ${PXCDIR}.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    rm -rf percona-xtradb-cluster  
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
    if [ $( id -u ) -ne 0 ]
    then
        echo "It is not possible to instal dependencies. Please run as root"
        exit 1
    fi    
    if [ "x$OS" = "xrpm" ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        add_percona_yum_repo
        yum -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm || true
        percona-release enable origin release
        yum -y install epel-release
        yum -y install git numactl-devel wget rpm-build gcc-c++ gperf ncurses-devel perl readline-devel openssl-devel jemalloc 
        yum -y install time zlib-devel libaio-devel bison cmake pam-devel libeatmydata jemalloc-devel
        yum -y install perl-Time-HiRes libcurl-devel openldap-devel unzip wget libcurl-devel boost-static scons check-devel
        yum -y install perl-Env perl-Data-Dumper perl-JSON MySQL-python perl-Digest perl-Digest-MD5 perl-Digest-Perl-MD5 || true

        if [ ${RHEL} -lt 7 -a $(uname -m) = x86_64 ]; then
            yum -y install percona-devtoolset-gcc percona-devtoolset-gcc-c++ percona-devtoolset-binutils 
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
        apt-get update
        apt-get -y install psmisc
        apt-get -y install libsasl2-modules:amd64 || apt-get -y install libsasl2-modules
        apt-get -y install dh-systemd || true
        apt-get -y install autoconf automake autotools-dev bison build-essential check chrpath cmake curl debconf debhelper devscripts \
                           fakeroot g++ gawk gcc gdb ghostscript git libaio-dev libasio-dev libboost-all-dev libc6-dbg libcurl-dev \
                           libcurl4-openssl-dev libeatmydata libjemalloc-dev libjson-perl libldap2-dev libmecab-dev libmecab2 \
                           libncurses5-dev libnuma-dev libpam-dev libreadline-dev libsasl2-dev libssl-dev libwrap0-dev lsb-release \
                           mecab mecab-ipadic openssl perl psmisc python-mysqldb scons socat unzip valgrind zlib1g-dev
    fi
    return;
}

get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -iname 'percona-xtradb-cluster*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -iname 'percona-xtradb-cluster*.tar.gz' | sort | tail -n1))
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
    FILE=$(basename $(find $WORKDIR/source_deb -iname "percona-xtradb-cluster*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -iname "percona-xtradb-cluster*.$param" | sort | tail -n1))
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
    cd $WORKDIR
    get_tar "source_tarball"
    rm -fr rpmbuild
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}

    TARFILE=$(basename $(find . -name 'Percona-XtraDB-Cluster-*.tar.gz' | sort | tail -n1))
    NAME="Percona-XtraDB-Cluster"
    VERSION=$MYSQL_VERSION
    RELEASE=$MYSQL_RELEASE

    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    #
    cd ${WORKDIR}/rpmbuild/SPECS
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/build-ps/*.spec' --strip=2
    #
    cd ${WORKDIR}
    #
    mv -fv ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES
    #
    sed -i "s:@@MYSQL_VERSION@@:${VERSION}:g" rpmbuild/SPECS/percona-xtradb-cluster.spec
    sed -i "s:@@PERCONA_VERSION@@:${RELEASE}:g" rpmbuild/SPECS/percona-xtradb-cluster.spec
    sed -i "s:@@WSREP_VERSION@@:${WSREP_VERSION}:g" rpmbuild/SPECS/percona-xtradb-cluster.spec
    sed -i "s:@@REVISION@@:${REVISION}:g" rpmbuild/SPECS/percona-xtradb-cluster.spec
    #

    SRCRPM=$(find . -name *.src.rpm)
    RHEL=$(rpm --eval %rhel)
    #
    ARCH=$(uname -m)
    if [ ${ARCH} = i686 ]; then
        ARCH=i386
    fi

    if test "x$(uname -m)" == "xx86_64"
    then
        SCONS_ARGS="bpostatic=/usr/lib64/libboost_program_options.a"
    else
        SCONS_ARGS=""
    fi
    source ${WORKDIR}/pxc-57.properties
    if test "x${SCONS_ARGS}" == "x"
        then
            rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "rpm_version $RPM_RELEASE" --define "galera_revision ${GALERA_REVNO}" --define "dist generic" rpmbuild/SPECS/percona-xtradb-cluster.spec
        else
            rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "rpm_version $RPM_RELEASE" --define "galera_revision ${GALERA_REVNO}" --define "dist generic" --define "scons_args ${SCONS_ARGS}" rpmbuild/SPECS/percona-xtradb-cluster.spec
    fi
    #
    echo "RPM_RELEASE=$RPM_RELEASE" >> pxc-57.properties

    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${WORKDIR}/srpm
    return
}

build_mecab_lib(){
    MECAB_TARBAL="mecab-0.996.tar.gz"
    MECAB_LINK="http://jenkins.percona.com/downloads/mecab/${MECAB_TARBAL}"
    MECAB_DIR="${WORKDIR}/${MECAB_TARBAL%.tar.gz}"
    MECAB_INSTALL_DIR="${WORKDIR}/mecab-install"
    rm -f ${MECAB_TARBAL}
    rm -rf ${MECAB_DIR}
    rm -rf ${MECAB_INSTALL_DIR}
    mkdir ${MECAB_INSTALL_DIR}
    wget ${MECAB_LINK}
    tar xf ${MECAB_TARBAL}
    cd ${MECAB_DIR}
    ./configure --with-pic --prefix=/usr
    make
    make check
    make DESTDIR=${MECAB_INSTALL_DIR} install
    cd ${WORKDIR}
}

build_mecab_dict(){
    MECAB_IPADIC_TARBAL="mecab-ipadic-2.7.0-20070801.tar.gz"
    MECAB_IPADIC_LINK="http://jenkins.percona.com/downloads/mecab/${MECAB_IPADIC_TARBAL}"
    MECAB_IPADIC_DIR="${WORKDIR}/${MECAB_IPADIC_TARBAL%.tar.gz}"
    rm -f ${MECAB_IPADIC_TARBAL}
    rm -rf ${MECAB_IPADIC_DIR}
    wget ${MECAB_IPADIC_LINK}
    tar xf ${MECAB_IPADIC_TARBAL}
    cd ${MECAB_IPADIC_DIR}
    # these two lines should be removed if proper packages are created and used for builds
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${MECAB_INSTALL_DIR}/usr/lib
    sed -i "/MECAB_DICT_INDEX=\"/c\MECAB_DICT_INDEX=\"${MECAB_INSTALL_DIR}\/usr\/libexec\/mecab\/mecab-dict-index\"" configure
    #
    ./configure --with-mecab-config=${MECAB_INSTALL_DIR}/usr/bin/mecab-config
    make
    make DESTDIR=${MECAB_INSTALL_DIR} install
    cd ../
    cd ${MECAB_INSTALL_DIR}
    if [ -d usr/lib64 ]; then
        mv usr/lib64/* usr/lib
    fi
    cd ${WORKDIR}
}

build_rpm(){
    if [ $RPM = 0 ]
    then
        echo "RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build rpm here"
        exit 1
    fi
    SRC_RPM=$(basename $(find $WORKDIR/srpm -iname 'Percona-XtraDB-Cluster*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -iname 'Percona-XtraDB-Cluster*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]
        then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
            exit 1
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
    echo "RHEL=${RHEL}" >> pxc-57.properties
    echo "ARCH=${ARCH}" >> pxc-57.properties
    #
    SRCRPM=$(basename $(find . -name '*.src.rpm' | sort | tail -n1))
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    #

    mv *.src.rpm rpmbuild/SRPMS
    if test "x$(uname -m)" == "xx86_64"
    then
        SCONS_ARGS="bpostatic=/usr/lib64/libboost_program_options.a"
    else
        SCONS_ARGS=""
    fi

    SCONS_ARGS+=" strict_build_flags=0"

    build_mecab_lib
    build_mecab_dict

    cd ${WORKDIR}
    #
    source ${WORKDIR}/pxc-57.properties
    if test "x${SCONS_ARGS}" == "x"
    then
        rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist el${RHEL}" --define "galera_revision ${GALERA_REVNO}" --define "rpm_version ${RPM_RELEASE}" --define "with_mecab ${MECAB_INSTALL_DIR}/usr" --rebuild rpmbuild/SRPMS/${SRCRPM}
        else
        rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist el${RHEL}" --define "galera_revision ${GALERA_REVNO}" --define "rpm_version ${RPM_RELEASE}" --define "scons_args ${SCONS_ARGS}" --define "with_mecab ${MECAB_INSTALL_DIR}/usr" --rebuild rpmbuild/SRPMS/${SRCRPM}
    fi
    return_code=$?
    if [ $return_code != 0 ]; then
        exit $return_code
    fi
    mkdir -p ${WORKDIR}/rpm
    mkdir -p ${CURDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${WORKDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${CURDIR}/rpm
    
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
    rm -rf percona-xtradb-cluster*
    get_tar "source_tarball"
    rm -f *.dsc *.orig.tar.gz *.debian.tar.gz *.changes
    #

    TARFILE=$(basename $(find . -iname 'percona-xtradb-cluster*.tar.gz' | grep -v tokudb | sort | tail -n1))
    NAME='percona-xtradb-cluster'
    HNAME='Percona-XtraDB-Cluster'

    VERSION=$MYSQL_VERSION
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    RELEASE=$MYSQL_RELEASE
    rm -fr ${HNAME}-${VERSION}-${WSREP_VERSION}

    #
    NEWTAR=${NAME}-${SHORTVER}_${VERSION}-${WSREP_VERSION}.orig.tar.gz
    mv ${TARFILE} ${NEWTAR}

    DEBIAN_VERSION="$(lsb_release -sc)"

    #
    tar xzf ${NEWTAR}
    cd ${HNAME}-${VERSION}-${WSREP_VERSION}
    cp -ap build-ps/debian/ .
    sed -i "s:@@MYSQL_VERSION@@:${VERSION}:g" debian/changelog
    sed -i "s:@@PERCONA_VERSION@@:${RELEASE}:g" debian/changelog

    sed -i "s:@@REVISION@@:${REVISION}:g" debian/rules
    sed -i "s:@@PERCONA_VERSION@@:${RELEASE}:g" debian/rules
    sed -i "s:@@WSREP_VERSION@@:${WSREP_VERSION}:g" debian/rules


    dch -D UNRELEASED --force-distribution -v "$MYSQL_VERSION-$WSREP_VERSION-$DEB_RELEASE" "Update to new upstream release Percona XtraDB Cluster ${VERSION}-rel${RELEASE}-$WSREP_VERSION"
    dpkg-buildpackage -S
    #
    rm -fr ${HNAME}-${VERSION}-${RELEASE}

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
        echo "source deb package will not be created"
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

    if test -e "/proc/cpuinfo"
    then
        PROCESSORS="$(grep -c ^processor /proc/cpuinfo)"
    else
        PROCESSORS=4
    fi
    export MAKE_JFLAG="${MAKE_JFLAG:--j$PROCESSORS}"
    ARCH=$(uname -m)
    DEBIAN_VERSION="$(lsb_release -sc)"

    COMMON_FLAGS="-Wall -Wp,-D_FORTIFY_SOURCE=2 -Wno-error=unused-result -Wno-error=literal-suffix -Wno-misleading-indentation -Wno-error=deprecated-declarations -Wno-error=nonnull-compare -DPERCONA_INNODB_VERSION=$MYSQL_RELEASE "
    export CFLAGS=" $COMMON_FLAGS -static-libgcc ${CFLAGS:-}"
    export CXXFLAGS=" $COMMON_FLAGS -Wno-virtual-move-assign  ${CXXFLAGS:-}"

    DSC=$(basename $(find . -name '*.dsc' | sort | tail -n 1))
    DIRNAME=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $1"-"$2"-"$3"-"$4"-"$5"-"$6}')
    rm -rf $DIRNAME

    #
    echo "ARCH=${ARCH}" >> ${WORKDIR}/pxc-57.properties
    echo "DEBIAN_VERSION=${DEBIAN_VERSION}" >> ${WORKDIR}/pxc-57.properties

    dpkg-source -x ${DSC}

    cd ${DIRNAME}

    if [[ "x$DEBIAN_VERSION" == "xbionic" || "x$DEBIAN_VERSION" == "xstretch" ]]; then
        sed -i 's/fabi-version=2/fabi-version=2 -Wno-error=deprecated-declarations -Wno-error=nonnull-compare -Wno-error=literal-suffix -Wno-misleading-indentation/' cmake/build_configurations/compiler_options.cmake
        sed -i 's/gnu++11/gnu++11 -Wno-virtual-move-assign/' cmake/build_configurations/compiler_options.cmake
    fi

    #==========
    export DEB_CFLAGS_APPEND="$CFLAGS" DEB_CXXFLAGS_APPEND="$CXXFLAGS"
    export MYSQL_BUILD_CFLAGS="$CFLAGS"
    export MYSQL_BUILD_CXXFLAGS="$CXXFLAGS"

    if [ ${DEBIAN_VERSION} = xenial -o ${DEBIAN_VERSION} = stretch -o ${DEBIAN_VERSION} = bionic ]; then
        rm -rf debian
        cp -r build-ps/ubuntu debian
        sed -i "s:@@MYSQL_VERSION@@:${MYSQL_VERSION}:g" debian/changelog
        sed -i "s:@@PERCONA_VERSION@@:${MYSQL_RELEASE}:g" debian/changelog
        sed -i "s:@@REVISION@@:${REVISION}:g" debian/rules
        sed -i "s:@@PERCONA_VERSION@@:${MYSQL_RELEASE}:g" debian/rules
        sed -i "s:@@WSREP_VERSION@@:${WSREP_VERSION}:g" debian/rules
    fi
    if [ x"${DEBIAN_VERSION}" = xbionic ]; then
        sed -i "s:iproute:iproute2:g" debian/control
    fi
    dch -b -m -D "$DEBIAN_VERSION" --force-distribution -v "$MYSQL_VERSION-$WSREP_VERSION-$DEB_RELEASE.${DEBIAN_VERSION}" 'Update distribution'
    #
    GALERA_REVNO="${GALERA_REVNO}" SCONS_ARGS=' strict_build_flags=0'  MAKE_JFLAG=-j4  dpkg-buildpackage -rfakeroot -uc -us -b
    #
    cd ${WORKDIR}
    rm -fv *.dsc *.orig.tar.gz *.debian.tar.gz *.changes 
    rm -fr ${DIRNAME}


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
    TARFILE=$(basename $(find . -iname 'percona-xtradb-cluster*.tar.gz' | sort | tail -n1))
    if [ -f /etc/debian_version ]; then
      export OS_RELEASE="$(lsb_release -sc)"
    fi
    #
    if [ -f /etc/redhat-release ]; then
      export OS_RELEASE="centos$(lsb_release -sr | awk -F'.' '{print $1}')"
      RHEL=$(rpm --eval %rhel)
    fi
    #

    ARCH=$(uname -m 2>/dev/null||true)
    JVERSION=${JEMALLOC_VERSION:-4.0.0}

    if [ -f /etc/redhat-release ]; then
        RHEL=$(rpm --eval %rhel 2>/dev/null||true)
        if [ ${RHEL} = 7 ]; then
            SSL_VER_TMP=$(yum list installed|grep -i openssl|head -n1|awk '{print $2}'|awk -F "-" '{print $1}'|sed 's/\.//g'|sed 's/[a-z]$//'| awk -F':' '{print $2}')
            export SSL_VER=".ssl${SSL_VER_TMP}"  
        else
            SSL_VER_TMP=$(yum list installed|grep -i openssl|head -n1|awk '{print $2}'|awk -F "-" '{print $1}'|sed 's/\.//g'|sed 's/[a-z]$//')
            export SSL_VER=".ssl${SSL_VER_TMP}"
        fi
    else
        SSL_VER_TMP=$(dpkg -l|grep -i libssl|grep -v "libssl\-"|head -n1|awk '{print $2}'|awk -F ":" '{print $1}'|sed 's/libssl/ssl/g'|sed 's/\.//g')
        export SSL_VER=".${SSL_VER_TMP}"
    fi

    ROOT_FS=$(pwd)

    TARFILE=$(basename $(find . -name 'Percona-XtraDB-Cluster-*.tar.gz' | grep -v 'galera' | sort | tail -n1))
    NAME="Percona-XtraDB-Cluster"
    VERSION=$MYSQL_VERSION
    RELEASE=$WSREP_VERSION

    export PXC_DIRNAME=$NAME-$VERSION-$WSREP_VERSION

    tar zxf $TARFILE
    rm -f $TARFILE
    #
    cd $PXC_DIRNAME
    BUILD_NUMBER=$(date "+%Y%m%d-%H%M%S")
    mkdir -p $BUILD_NUMBER

    BUILD_ROOT="$ROOT_FS/$PXC_DIRNAME/$BUILD_NUMBER"

    rm -rf jemalloc
    wget https://github.com/jemalloc/jemalloc/releases/download/$JVERSION/jemalloc-$JVERSION.tar.bz2
    tar xf jemalloc-$JVERSION.tar.bz2
    mv jemalloc-$JVERSION jemalloc 

    export SCONS_ARGS=" strict_build_flags=0"
    bash -x ./build-ps/build-binary.sh --with-jemalloc=jemalloc/ -t 1.1 $BUILD_ROOT

    mv $BUILD_NUMBER/*.tar.gz $ROOT_FS
    
    mkdir -p ${WORKDIR}/${DIRNAME}
    mkdir -p ${CURDIR}/${DIRNAME}
    cp ../TARGET/*.tar.gz ${WORKDIR}/${DIRNAME}
    cp ../TARGET/*.tar.gz ${CURDIR}/${DIRNAME}
}

#main

CURDIR=$(pwd)
VERSION_FILE=$CURDIR/pxc-57.properties
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
INSTALL=0
RPM_RELEASE=1
DEB_RELEASE=1
REVISION=0
BRANCH="5.7"
MECAB_INSTALL_DIR="${WORKDIR}/mecab-install"
REPO="git://github.com/percona/percona-xtradb-cluster.git"
PRODUCT=Percona-XtraDB-Cluster-5.7
MYSQL_VERSION=5.7.24
MYSQL_RELEASE=26
WSREP_VERSION=31.33
PRODUCT_FULL=Percona-XtraDB-Cluster-5.7.24-31.33
parse_arguments PICK-ARGS-FROM-ARGV "$@"

check_workdir
get_system
install_deps
get_sources
build_tarball
build_srpm
build_source_deb
build_rpm
build_deb