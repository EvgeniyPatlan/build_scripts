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
        --build_src_rpm     If it is set - src rpm will be built
        --build_source_deb  If it is set - source deb package will be built
        --build_rpm         If it is set - rpm will be built
        --build_deb         If it is set - deb will be built
        --build_tarball     If it is set - tarball will be built
        --install_deps      Install build dependencies(root privilages are required)
        --branch            Branch for build
        --repo              Repo for build
        --psm_ver           PSM_VER(mandatory)
        --psm_release       PSM_RELEASE(mandatory)
        --mongo_tools_tag   MONGO_TOOLS_TAG(mandatory)
        --debug             build debug tarball
        
        --help) usage ;;
Example $0 --builddir=/tmp/PSMDB --get_sources=1 --build_src_rpm=1 --build_rpm=1
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
            --psm_ver=*) PSM_VER="$val" ;;
            --psm_release=*) PSM_RELEASE="$val" ;;
            --mongo_tools_tag=*) MONGO_TOOLS_TAG="$val" ;;
            --debug=*) DEBUG="$val" ;;
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
      wget http://jenkins.percona.com/yum-repo/percona-dev.repo
      mv -f percona-dev.repo /etc/yum.repos.d/
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

get_sources(){
    cd "${WORKDIR}"
    if [ "${SOURCE}" = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi
    PRODUCT=percona-server-mongodb
    echo "PRODUCT=${PRODUCT}" > percona-server-mongodb-36.properties

    PRODUCT_FULL=${PRODUCT}-${PSM_VER}-${PSM_RELEASE}
    echo "PRODUCT_FULL=${PRODUCT_FULL}" >> percona-server-mongodb-36.properties
    echo "VERSION=${PSM_VER}" >> percona-server-mongodb-36.properties
    echo "RELEASE=$PSM_RELEASE" >> percona-server-mongodb-36.properties
    echo "PSM_BRANCH=${PSM_BRANCH}" >> percona-server-mongodb-36.properties
    echo "JEMALLOC_TAG=${JEMALLOC_TAG}" >> percona-server-mongodb-36.properties
    echo "MONGO_TOOLS_TAG=${MONGO_TOOLS_TAG}" >> percona-server-mongodb-36.properties
    echo "BUILD_NUMBER=${BUILD_NUMBER}" >> percona-server-mongodb-36.properties
    echo "BUILD_ID=${BUILD_ID}" >> percona-server-mongodb-36.properties
    git clone "$REPO"
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi
    cd percona-server-mongodb
    if [ ! -z "$BRANCH" ]
    then
        git reset --hard
        git clean -xdf
        git checkout "$BRANCH"
    fi
    REVISION=$(git rev-parse --short HEAD)
    # create a proper version.json
    REVISION_LONG=$(git rev-parse HEAD)
    echo "{" > version.json
    echo "    \"version\": \"${PSM_VER}-${PSM_RELEASE}\"," >> version.json
    echo "    \"githash\": \"${REVISION_LONG}\"" >> version.json
    echo "}" >> version.json
    #
    echo "REVISION=${REVISION}" >> ${WORKDIR}/percona-server-mongodb-36.properties
    rm -fr debian rpm
    cp -a percona-packaging/manpages .
    cp -a percona-packaging/docs/* .
    #
    # submodules
    git submodule init
    git submodule update
    #
    git clone https://github.com/mongodb/mongo-tools.git
    cd mongo-tools
    git checkout $MONGO_TOOLS_TAG
    echo "export PSMDB_TOOLS_COMMIT_HASH=\"$(git rev-parse HEAD)\"" > set_tools_revision.sh
    echo "export PSMDB_TOOLS_REVISION=\"${PSM_VER}-${PSM_RELEASE}\"" >> set_tools_revision.sh
    chmod +x set_tools_revision.sh
    cd ${WORKDIR}
    #
    #source ${WORKDIR}/percona-server-mongodb-36.properties
    #
    source percona-server-mongodb-36.properties
    #
    sed -i 's:/bin/sh:/bin/sh -x:' percona-server-mongodb/src/third_party/rocksdb/build_tools/build_detect_platform

    mv percona-server-mongodb ${PRODUCT}-${PSM_VER}-${PSM_RELEASE}
    tar --owner=0 --group=0 --exclude=.* -czf ${PRODUCT}-${PSM_VER}-${PSM_RELEASE}.tar.gz ${PRODUCT}-${PSM_VER}-${PSM_RELEASE}
    echo "UPLOAD=UPLOAD/experimental/BUILDS/${PRODUCT}-3.6/${PRODUCT}-${PSM_VER}-${PSM_RELEASE}/${PSM_BRANCH}/${REVISION}/${BUILD_ID}" >> percona-server-mongodb-36.properties
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp ${PRODUCT}-${PSM_VER}-${PSM_RELEASE}.tar.gz $WORKDIR/source_tarball
    cp ${PRODUCT}-${PSM_VER}-${PSM_RELEASE}.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    rm -rf percona-server-mongodb   
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

install_golang() {
    wget http://jenkins.percona.com/downloads/golang/go1.8.linux-amd64.tar.gz -O /tmp/golang1.8.tar.gz
    tar --transform=s,go,go1.8, -zxf /tmp/golang1.8.tar.gz
    rm -rf /usr/local/go1.8 /usr/local/go1.9 /usr/local/go1.9.2 /usr/local/go
    mv go1.8 /usr/local/
    ln -s /usr/local/go1.8 /usr/local/go
}

install_gcc_54_centos(){
    wget http://jenkins.percona.com/downloads/gcc-5.4.0/gcc-5.4.0_centos-$RHEL-x64.tar.gz -O /tmp/gcc-5.4.0_centos-$RHEL-x64.tar.gz
    tar -zxf /tmp/gcc-5.4.0_centos-$RHEL-x64.tar.gz
    rm -rf /usr/local/gcc-5.4.0
    mv gcc-5.4.0 /usr/local/
    echo "OUTPUT_FORMAT(elf64-x86-64)" > libstdc++.so && echo "INPUT ( /usr/local/gcc-5.4.0/lib64/libstdc++.a )" >> libstdc++.so
    mv libstdc++.so /usr/local/gcc-5.4.0/lib64/
}

install_gcc_54_deb(){
    if [ x"${DEBIAN}" = xwheezy -o x"${DEBIAN}" = xjessie ]; then
        wget https://jenkins.percona.com/downloads/gcc-5.4.0/gcc-5.4.0_debian-${DEBIAN}-x64.tar.gz -O /tmp/gcc-5.4.0_debian-${DEBIAN}-x64.tar.gz
        tar -zxf /tmp/gcc-5.4.0_debian-${DEBIAN}-x64.tar.gz
        rm -rf /usr/local/gcc-5.4.0
        mv gcc-5.4.0 /usr/local/
        if [ x"${DEBIAN}" = xjessie ]; then
            echo "OUTPUT_FORMAT(elf64-x86-64)" > libstdc++.so && echo "INPUT ( /usr/local/gcc-5.4.0/lib64/libstdc++.a )" >> libstdc++.so
            mv libstdc++.so /usr/local/gcc-5.4.0/lib64/
        fi
    fi
    if [ x"${DEBIAN}" = xtrusty -o x"${DEBIAN}" = xxenial ]; then
        wget https://jenkins.percona.com/downloads/gcc-5.4.0/gcc-5.4.0_ubuntu-${DEBIAN}-x64.tar.gz -O /tmp/gcc-5.4.0_ubuntu-${DEBIAN}-x64.tar.gz
        tar -zxf /tmp/gcc-5.4.0_ubuntu-${DEBIAN}-x64.tar.gz
        rm -rf /usr/local/gcc-5.4.0
        mv gcc-5.4.0 /usr/local/
    fi
}

set_compiler(){
    if [ x"${DEBIAN}" = xjessie -o x"${DEBIAN}" = xwheezy -o x"${DEBIAN}" = xtrusty -o x"${DEBIAN}" = xxenial ]; then
        export CC=/usr/local/gcc-5.4.0/bin/gcc-5.4
	    export CXX=/usr/local/gcc-5.4.0/bin/g++-5.4
    fi
    if [ x"${DEBIAN}" = xstretch ]; then
        export CC=/usr/bin/gcc-6
	    export CXX=/usr/bin/g++-6
    fi
    if [ x"${DEBIAN}" = xartful -o x"${DEBIAN}" = xbionic ]; then
        export CC=/usr/bin/gcc-7
	    export CXX=/usr/bin/g++-7
    fi
}

fix_rules(){
    if [ x"${DEBIAN}" = xjessie -o x"${DEBIAN}" = xwheezy -o x"${DEBIAN}" = xtrusty -o x"${DEBIAN}" = xxenial ]; then
        sed -i 's|CC = gcc-5|CC = /usr/local/gcc-5.4.0/bin/gcc-5.4|' debian/rules
        sed -i 's|CXX = g++-5|CXX = /usr/local/gcc-5.4.0/bin/g++-5.4|' debian/rules
    fi
    if [ x"${DEBIAN}" = xstretch ]; then
        sed -i 's|CC = gcc-5|CC = /usr/bin/gcc-6|' debian/rules
        sed -i 's|CXX = g++-5|CXX = /usr/bin/g++-6|' debian/rules  
        sed -i 's|CC = /usr/local/gcc-5.4.0/bin/gcc-5.4|CC = /usr/bin/gcc-6|' debian/rules
        sed -i 's|CXX = /usr/local/gcc-5.4.0/bin/g++-5.4|CXX = /usr/bin/g++-6|' debian/rules
        sed -i 's:release:release --disable-warnings-as-errors :g' debian/rules 
    fi
    if [ x"${DEBIAN}" = xartful -o x"${DEBIAN}" = xbionic ]; then
        sed -i 's|CC = gcc-5|CC = /usr/bin/gcc-7|' debian/rules
        sed -i 's|CXX = g++-5|CXX = /usr/bin/g++-7|' debian/rules
        sed -i 's|CC = /usr/local/gcc-5.4.0/bin/gcc-5.4|CC = /usr/bin/gcc-7|' debian/rules
        sed -i 's|CXX = /usr/local/gcc-5.4.0/bin/g++-5.4|CXX = /usr/bin/g++-7|' debian/rules
        sed -i 's:release:release --disable-warnings-as-errors :g' debian/rules 
    fi
    if [ x"${DEBIAN}" = xbionic ]; then
        sed -i "s/-Werror//g" src/third_party/PerconaFT/cmake_modules/TokuSetupCompiler.cmake
    fi
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
      yum -y install wget
      add_percona_yum_repo
      wget http://jenkins.percona.com/yum-repo/percona-dev.repo
      mv -f percona-dev.repo /etc/yum.repos.d/
      yum clean all
      yum -y install epel-release
      rm -fr /usr/local/gcc-5.4.0
      RHEL=$(rpm --eval %rhel)
      if [ x"$RHEL" = x6 ]; then
        yum -y install rpmbuild rpm-build libpcap-devel gcc make cmake gcc-c++ openssl-devel cyrus-sasl-devel snappy-devel zlib-devel bzip2-devel libpcap-devel scons make rpm-build rpmbuild percona-devtoolset-gcc percona-devtoolset-binutils percona-devtoolset-gcc-c++ percona-devtoolset-libstdc++-devel percona-devtoolset-valgrind-devel python27 python27-devel
        wget https://bootstrap.pypa.io/get-pip.py
        python2.7 get-pip.py
        rm -rf /usr/bin/python2
        ln -s /usr/bin/python2.7 /usr/bin/python2
      else
        yum -y install rpmbuild rpm-build libpcap-devel gcc make cmake gcc-c++ openssl-devel cyrus-sasl-devel snappy-devel zlib-devel bzip2-devel scons rpmlint rpm-build git python-pip python-devel libopcodes
      fi
      install_golang
      install_gcc_54_centos
    else
      export DEBIAN=$(lsb_release -sc)
      export ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
      INSTALL_LIST="python python-dev valgrind scons liblz4-dev devscripts debhelper debconf libpcap-dev libbz2-dev libsnappy-dev pkg-config zlib1g-dev libzlcore-dev dh-systemd libsasl2-dev gcc g++ cmake "
      if [ x"${DEBIAN}" = xstretch -o x"${DEBIAN}" = xbionic -o x"${DEBIAN}" = xartful ]; then
        INSTALL_LIST="${INSTALL_LIST} libssl1.0-dev"
      else
        INSTALL_LIST="${INSTALL_LIST} libssl-dev"
      fi
      until apt-get -y install dirmngr; do
        sleep 1
        echo "waiting"
      done
      add_percona_apt_repo
      until apt-get update; do
        sleep 1
        echo "waiting"
      done
      until apt-get -y install ${INSTALL_LIST}; do
        sleep 1
        echo "waiting"
      done
      install_golang
      install_gcc_54_deb
      wget https://bootstrap.pypa.io/get-pip.py
      python get-pip.py
      easy_install pip
    fi
    return;
}

get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'percona-server-mongodb*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'percona-server-mongodb*.tar.gz' | sort | tail -n1))
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
    FILE=$(basename $(find $WORKDIR/source_deb -name "percona-server-mongodb*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -name "percona-server-mongodb*.$param" | sort | tail -n1))
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
    ls | grep -v tar.gz | xargs rm -rf
    TARFILE=$(find . -name 'percona-server-mongodb-*.tar.gz' | sort | tail -n1)
    SRC_DIR=${TARFILE%.tar.gz}
    #
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/percona-packaging' --strip=1
    SPEC_TMPL=$(find percona-packaging/redhat -name 'percona-server-mongodb.spec.template' | sort | tail -n1)
    #
    cp -av percona-packaging/conf/* rpmbuild/SOURCES
    cp -av percona-packaging/redhat/mongod.* rpmbuild/SOURCES
    #
    sed -i 's:@@LOCATION@@:sysconfig:g' rpmbuild/SOURCES/*.service
    sed -i 's:@@LOCATION@@:sysconfig:g' rpmbuild/SOURCES/percona-server-mongodb-helper.sh
    sed -i 's:@@LOGDIR@@:mongo:g' rpmbuild/SOURCES/*.default
    sed -i 's:@@LOGDIR@@:mongo:g' rpmbuild/SOURCES/percona-server-mongodb-helper.sh
    #
    sed -e "s:@@SOURCE_TARBALL@@:$(basename ${TARFILE}):g" \
    -e "s:@@VERSION@@:${VERSION}:g" \
    -e "s:@@RELEASE@@:${RELEASE}:g" \
    -e "s:@@SRC_DIR@@:$SRC_DIR:g" \
    ${SPEC_TMPL} > rpmbuild/SPECS/$(basename ${SPEC_TMPL%.template})
    mv -fv ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES
    rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .generic" rpmbuild/SPECS/$(basename ${SPEC_TMPL%.template})
    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${WORKDIR}/srpm
    return
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
    SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'Percona-Server-MongoDB-*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'Percona-Server-MongoDB-*.src.rpm' | sort | tail -n1))
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

    cd rpmbuild/SRPMS/
    rpm2cpio ${SRC_RPM} | cpio -id
    TARF=$(find . -name 'percona-server-mongodb-*.tar.gz' | sort | tail -n1)
    tar vxzf ${TARF} --wildcards '*/buildscripts' --strip=1
    if [ "x${RHEL}" == "x6" ]; then
    pip2.7 install --user -r buildscripts/requirements.txt
    else
    pip install --user -r buildscripts/requirements.txt
    fi
    #
    cd $WORKDIR
    if [ -f /opt/percona-devtoolset/enable ]; then
    . /opt/percona-devtoolset/enable
    fi

    RHEL=$(rpm --eval %rhel)
    ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')

    echo "CC and CXX should be modified once correct compiller would be installed on Centosed"
    export CC=/usr/local/gcc-5.4.0/bin/gcc-5.4
    export CXX=/usr/local/gcc-5.4.0/bin/g++-5.4
    #
    echo "RHEL=${RHEL}" >> percona-server-mongodb-36.properties
    echo "ARCH=${ARCH}" >> percona-server-mongodb-36.properties
    #
    file /usr/bin/scons
    #
    #if [ "x${RHEL}" == "x6" ]; then
        [[ ${PATH} == *"/usr/local/go/bin"* && -x /usr/local/go/bin/go ]] || export PATH=/usr/local/go/bin:${PATH}
        export GOROOT="/usr/local/go/"
        export GOPATH=$(pwd)/
        export PATH="/usr/local/go/bin:$PATH:$GOPATH"
        export GOBINPATH="/usr/local/go/bin"
    #fi
    rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .$OS_NAME" --rebuild rpmbuild/SRPMS/$SRC_RPM

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
    rm -rf percona-server-mongodb*
    get_tar "source_tarball"
    rm -f *.dsc *.orig.tar.gz *.debian.tar.gz *.changes
    #
    TARFILE=$(basename $(find . -name 'percona-server-mongodb-*.tar.gz' | sort | tail -n1))
    DEBIAN=$(lsb_release -sc)
    ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    tar zxf ${TARFILE} 
    BUILDDIR=${TARFILE%.tar.gz}
    #
    rm -fr ${BUILDDIR}/debian
    cp -av ${BUILDDIR}/percona-packaging/debian ${BUILDDIR}
    cp -av ${BUILDDIR}/percona-packaging/conf/* ${BUILDDIR}/debian/
    #
    sed -i 's:@@LOCATION@@:default:g' ${BUILDDIR}/debian/*.service
    sed -i 's:@@LOCATION@@:default:g' ${BUILDDIR}/debian/percona-server-mongodb-helper.sh
    sed -i 's:@@LOGDIR@@:mongodb:g' ${BUILDDIR}/debian/mongod.default
    sed -i 's:@@LOGDIR@@:mongodb:g' ${BUILDDIR}/debian/percona-server-mongodb-helper.sh
    #
    mv ${BUILDDIR}/debian/mongod.default ${BUILDDIR}/debian/percona-server-mongodb-36-server.mongod.default
    mv ${BUILDDIR}/debian/mongod.service ${BUILDDIR}/debian/percona-server-mongodb-36-server.mongod.service
    #
    mv ${TARFILE} ${PRODUCT}-36_${VERSION}.orig.tar.gz
    cd ${BUILDDIR}
    #pip install -r buildscripts/requirements.txt

    set_compiler
    fix_rules

    dch -D unstable --force-distribution -v "${VERSION}-${RELEASE}" "Update to new Percona Server for MongoDB version ${VERSION}"
    dpkg-buildpackage -S
    cd ../
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
    #
    export DEBIAN=$(lsb_release -sc)
    export ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    #
    echo "DEBIAN=${DEBIAN}" >> percona-server-mongodb-36.properties
    echo "ARCH=${ARCH}" >> percona-server-mongodb-36.properties

    #
    DSC=$(basename $(find . -name '*.dsc' | sort | tail -n1))
    #
    dpkg-source -x ${DSC}
    #
    cd ${PRODUCT}-36-${VERSION}
    pip install --user -r buildscripts/requirements.txt
    #
    set_compiler
    fix_rules
    dch -m -D "${DEBIAN}" --force-distribution -v "${VERSION}-${RELEASE}.${DEBIAN}" 'Update distribution'

    dpkg-buildpackage -rfakeroot -us -uc -b
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
    TARFILE=$(basename $(find . -name 'percona-server-mongodb-*.tar.gz' | sort | tail -n1))

    if [ -f /opt/percona-devtoolset/enable ]; then
    source /opt/percona-devtoolset/enable
    fi
    #
    export DEBIAN_VERSION="$(lsb_release -sc)"
    export DEBIAN="$(lsb_release -sc)"
    export PATH=/usr/local/go/bin:$PATH
    #
    if [ -f /etc/debian_version ]; then
        if [ x"${DEBIAN}" = xwheezy -o x"${DEBIAN}" = xjessie -o x"${DEBIAN}" = xtrusty -o x"${DEBIAN}" = xxenial ]; then
            export CC=/usr/local/gcc-5.4.0/bin/gcc-5.4
            export CXX=/usr/local/gcc-5.4.0/bin/g++-5.4
        else
            export CC=gcc-5
            export CXX=g++-5
        fi
    else
        export CC=/usr/local/gcc-5.4.0/bin/gcc-5.4
        export CXX=/usr/local/gcc-5.4.0/bin/g++-5.4
        
    fi
    #

    PSM_TARGETS="mongod mongos mongo mongobridge"
    TARBALL_SUFFIX=""
    if [ ${DEBUG} = 1 ]; then
    TARBALL_SUFFIX=".dbg"
    fi
    if [ -f /etc/debian_version ]; then
    export OS_RELEASE="$(lsb_release -sc)"
    fi
    #
    if [ -f /etc/redhat-release ]; then
    #export OS_RELEASE="centos$(lsb_release -sr | awk -F'.' '{print $1}')"
    export OS_RELEASE="centos$(rpm --eval %rhel)"
    RHEL=$(rpm --eval %rhel)
    fi
    #
    ARCH=$(uname -m 2>/dev/null||true)
    TARFILE=$(basename $(find . -name 'percona-server-mongodb-*.tar.gz' | sort | grep -v "tools" | tail -n1))
    PSMDIR=${TARFILE%.tar.gz}
    PSMDIR_ABS=${WORKDIR}/${PSMDIR}
    TOOLSDIR=${PSMDIR}/mongo-tools
    TOOLSDIR_ABS=${WORKDIR}/${TOOLSDIR}
    TOOLS_TAGS="ssl sasl"
    NJOBS=4

    tar xzf $TARFILE
    rm -f $TARFILE

    rm -fr /tmp/${PSMDIR}
    ln -fs ${PSMDIR_ABS} /tmp/${PSMDIR}
    cd /tmp
    #
    export CFLAGS="${CFLAGS:-} -fno-omit-frame-pointer"
    export CXXFLAGS="${CFLAGS}"
    if [ ${DEBUG} = 1 ]; then
    export CXXFLAGS="${CFLAGS} -Wno-error=deprecated-declarations"
    fi
    export INSTALLDIR=${WORKDIR}/install
    export PORTABLE=1
    export USE_SSE=1
    #
    # RocksDB
    pushd ${PSMDIR}/src/third_party/rocksdb
    if [ ${DEBUG} = 0 ]; then
        make -j4 EXTRA_CFLAGS='-fPIC -DLZ4 -I../lz4-r131 -DSNAPPY -I../snappy-1.1.3 -DHAVE_SSE42' EXTRA_CXXFLAGS='-fPIC -DLZ4 -I../lz4-r131 -DSNAPPY -I../snappy-1.1.3 -DHAVE_SSE42' DISABLE_JEMALLOC=1 static_lib
    else
        make -j4 'EXTRA_CFLAGS=-fPIC -DLZ4 -I../lz4-r131 -DSNAPPY -I../snappy-1.1.3 -DHAVE_SSE42' 'EXTRA_CXXFLAGS=-fPIC -DLZ4 -I../lz4-r131 -DSNAPPY -I../snappy-1.1.3 -DHAVE_SSE42' DISABLE_JEMALLOC=1 DEBUG_LEVEL=2 static_lib
    fi
    rm -rf ${INSTALLDIR}
    mkdir -p ${INSTALLDIR}/include
    mkdir -p ${INSTALLDIR}/bin
    mkdir -p ${INSTALLDIR}/lib
    if [ ${DEBUG} = 0 ]; then
        make install-static INSTALL_PATH=${INSTALLDIR}
    else
        make -j$NJOBS DEBUG_LEVEL=2 static_lib
        make install-static INSTALL_PATH=${INSTALLDIR}
    fi
    popd
    #
    # Finally build Percona Server for MongoDB with SCons
    cd ${PSMDIR_ABS}
    pip install --user -r buildscripts/requirements.txt
    if [ ${DEBUG} = 0 ]; then
        buildscripts/scons.py CC=${CC} CXX=${CXX} --release --ssl --opt=on -j$NJOBS --use-sasl-client --wiredtiger --audit --rocksdb --inmemory --hotbackup CPPPATH=${INSTALLDIR}/include LIBPATH=${INSTALLDIR}/lib ${PSM_TARGETS}
    else
        buildscripts/scons.py CC=${CC} CXX=${CXX} --disable-warnings-as-errors --audit --ssl --dbg=on -j$NJOBS --use-sasl-client \
        CPPPATH=${INSTALLDIR}/include LIBPATH=${INSTALLDIR}/lib --rocksdb --wiredtiger --inmemory --hotbackup ${PSM_TARGETS}
    fi
    #
    # scons install doesn't work - it installs the binaries not linked with fractal tree
    #scons --prefix=$PWD/$PSMDIR install
    #
    mkdir -p ${PSMDIR}/bin
    if [ ${DEBUG} = 0 ]; then
    for target in ${PSM_TARGETS[@]}; do
        cp -f $target ${PSMDIR}/bin
        strip --strip-debug ${PSMDIR}/bin/${target}
    done
    fi
    #
    cd ${WORKDIR}
    #
    # Build mongo tools
    cd ${TOOLSDIR}
    rm -rf vendor/pkg
    [[ ${PATH} == *"/usr/local/go/bin"* && -x /usr/local/go/bin/go ]] || export PATH=/usr/local/go/bin:${PATH}
    export GOROOT="/usr/local/go/"
    export GOPATH=$(pwd)/
    export PATH="/usr/local/go/bin:$PATH:$GOPATH"
    export GOBINPATH="/usr/local/go/bin"
    . ./set_gopath.sh
    . ./set_tools_revision.sh
    mkdir -p bin
    for i in bsondump mongostat mongofiles mongoexport mongoimport mongorestore mongodump mongotop mongoreplay; do
    echo "Building ${i}..."
    if [ ${DEBUG} = 0 ]; then
        go build -a -x -o "bin/$i" -ldflags "-X github.com/mongodb/mongo-tools/common/options.Gitspec=${PSMDB_TOOLS_COMMIT_HASH} -X github.com/mongodb/mongo-tools/common/options.VersionStr=${PSMDB_TOOLS_REVISION}" -tags "${TOOLS_TAGS}" "$i/main/$i.go"
    else
        go build -a -o "bin/$i" -ldflags "-X github.com/mongodb/mongo-tools/common/options.Gitspec=${PSMDB_TOOLS_COMMIT_HASH} -X github.com/mongodb/mongo-tools/common/options.VersionStr=${PSMDB_TOOLS_REVISION}" -tags "${TOOLS_TAGS}" "$i/main/$i.go"
    fi
    done
    # move mongo tools to PSM installation dir
    mv bin/* ${PSMDIR_ABS}/${PSMDIR}/bin
    # end build tools
    #
    sed -i "s:TARBALL=0:TARBALL=1:" ${PSMDIR_ABS}/percona-packaging/conf/percona-server-mongodb-enable-auth.sh
    cp ${PSMDIR_ABS}/percona-packaging/conf/percona-server-mongodb-enable-auth.sh ${PSMDIR_ABS}/${PSMDIR}/bin

    cd ${PSMDIR_ABS}
    tar --owner=0 --group=0 -czf ${WORKDIR}/${PSMDIR}-${OS_RELEASE}-${ARCH}${TARBALL_SUFFIX}.tar.gz ${PSMDIR}
    DIRNAME="tarball"
    if [ "${DEBUG}" = 1 ]; then
    DIRNAME="debug"
    fi
    mkdir -p ${WORKDIR}/${DIRNAME}
    mkdir -p ${CURDIR}/${DIRNAME}
    cp ${WORKDIR}/${PSMDIR}-${OS_RELEASE}-${ARCH}${TARBALL_SUFFIX}.tar.gz ${WORKDIR}/${DIRNAME}
    cp ${WORKDIR}/${PSMDIR}-${OS_RELEASE}-${ARCH}${TARBALL_SUFFIX}.tar.gz ${CURDIR}/${DIRNAME}
}

#main

CURDIR=$(pwd)
VERSION_FILE=$CURDIR/percona-server-mongodb.properties
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
BRANCH="v3.6"
REPO="https://github.com/percona/percona-server-mongodb.git"
PSM_VER="3.6.3"
VERSION=${PSM_VER}
PSM_RELEASE="1.1"
RELEASE=${PSM_RELEASE}
MONGO_TOOLS_TAG="r3.6.3"
PRODUCT=percona-server-mongodb
DEBUG=0
PRODUCT_FULL=${PRODUCT}-${PSM_VER}-${PSM_RELEASE}
parse_arguments PICK-ARGS-FROM-ARGV "$@"
PSM_BRANCH=${BRANCH}
if [ ${DEBUG} = 1 ]; then
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