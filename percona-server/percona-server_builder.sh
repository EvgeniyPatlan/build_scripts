#!/bin/sh
CURDIR=$(pwd)
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
BRANCH="5.7"
INSTALL=0
RPM_RELEASE=1
DEB_RELEASE=1
REVISION=0
PERCONAFT_REPO=''
PERCONAFT_BRANCH=''
TOKUBACKUP_REPO=''
TOKUBACKUP_BRANCH=''
BOOST_PACKAGE_NAME='boost_1_59_0'


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
        --build_source_deb   If it is 1 source deb package will be built
        --build_rpm         If it is 1 rpm will be built
        --build_deb         If it is 1 deb will be built
        --build_tarball     If it is 1 tarball will be built
        --install_deps       Install build dependencies(root previlages are required)
        --help) usage ;;
Example $0 --builddir=/tmp/build --get_sources=1 --build_src_rpm=1 --build_rpm=1
EOF
        exit 1
}

append_arg_to_args () {
  args="$args "`shell_quote_string "$1"`
}

parse_arguments() {
    pick_args=
    if test "$1" = PICK-ARGS-FROM-ARGV
    then
        pick_args=1
        shift
    fi
  
    for arg do
        val=`echo "$arg" | sed -e 's;^--[^=]*=;;'`
        optname=`echo "$arg" | sed -e 's/^\(--[^=]*\)=.*$/\1/'`
        case "$arg" in
            # these get passed explicitly to mysqld
            --builddir=*)
              WORKDIR="$val"
              WORKDIR=$WORKDIR
            ;;
            --build_src_rpm=*) SRPM="$val" ;;
            --build_source_deb=*) SDEB="$val" ;;
            --build_rpm=*) RPM="$val" ;;
            --build_deb=*) DEB="$val" ;;
            --get_sources=*) SOURCE="$val" ;;
            --build_tarball=*) TARBALL="$val" ;;
            --branch=*) BRANCH="$val" ;;
            --install_deps=*) INSTALL="$val" ;;
            --perconaft_branch=*)
              PERCONAFT_BRANCH="$val"
              if [ -z $PERCONAFT_BRANCH ]; then
                  PERCONAFT_BRANCH='master'
              fi
              ;;
              --tokubackup_branch=*)
              TOKUBACKUP_BRANCH="$val"
              if [ -z $TOKUBACKUP_BRANCH ]; then
                  TOKUBACKUP_BRANCH_BRANCH='master'
              fi
              ;;
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
    if [ ! -f /etc/apt/sources.list.d/percona-dev.list ]
    then
        cat >/etc/apt/sources.list.d/percona-dev.list <<EOL
deb http://jenkins.percona.com/apt-repo/ @@DIST@@ main
deb-src http://jenkins.percona.com/apt-repo/ @@DIST@@ main
EOL
    sed -i "s:@@DIST@@:$OS_NAME:g" /etc/apt/sources.list.d/percona-dev.list
    fi
    return
}


get_sources(){
    cd $WORKDIR
    if [ $SOURCE = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi
    git clone https://github.com/percona/percona-server.git
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi
    cd percona-server
    if [ ! -z $BRANCH ]
    then
        git checkout $BRANCH
    fi
    REVISION=$(git rev-parse --short HEAD)
    git reset --hard
    #
    source ./VERSION
    BRANCH_NAME="${BRANCH}"
    BOOST_PACKAGE_NAME=$(cat cmake/boost.cmake|grep "SET(BOOST_PACKAGE_NAME"|awk -F '"' '{print $2}')
    rm -rf storage/tokudb/PerconaFT
    rm -rf plugin/tokudb-backup-plugin/Percona-TokuBackup

    if [ -z $PERCONAFT_REPO -a -z $TOKUBACKUP_REPO ]; then
      mkdir plugin/tokudb-backup-plugin/Percona-TokuBackup
      mkdir storage/tokudb/PerconaFT
      git submodule init
      git submodule update
      cd storage/tokudb/PerconaFT
      git fetch origin
      git checkout $PERCONAFT_BRANCH
      if [ "x$PERCONAFT_BRANCH" = 'xmaster' ]; then
        git pull
      fi
      cd ../../../
      cd plugin/tokudb-backup-plugin/Percona-TokuBackup
      git fetch origin
      git checkout $TOKUBACKUP_BRANCH
      if [ "x$TOKUBACKUP_BRANCH" = 'xmaster' ]; then
        git pull
      fi
      cd ../../../
    else
      cd storage/tokudb
      git clone $PERCONAFT_REPO
      cd PerconaFT
      git checkout $PERCONAFT_BRANCH
      cd $WORKDIR/percona-server
      cd plugin/tokudb-backup-plugin
      git clone $TOKUBACKUP_REPO
      cd Percona-TokuBackup
      git checkout $TOKUBACKUP_BRANCH
      cd $WORKDIR/percona-server
    fi
    git submodule update
    cmake . -DDOWNLOAD_BOOST=1 -DWITH_BOOST=$WORKDIR/build-ps/boost
    make dist
    EXPORTED_TAR=$(basename $(find . -type f -name *.tar.gz | sort | tail -n 1))
    PSDIR=${EXPORTED_TAR%.tar.gz}
    rm -fr $PSDIR
    tar xzf $EXPORTED_TAR
    rm -f $EXPORTED_TAR
    rsync -av storage/tokudb/PerconaFT $PSDIR/storage/tokudb --exclude .git
    rsync -av plugin/tokudb-backup-plugin/Percona-TokuBackup $PSDIR/plugin/tokudb-backup-plugin --exclude .git
    rsync -av storage/rocksdb/rocksdb/ $PSDIR/storage/rocksdb/rocksdb --exclude .git
    rsync -av storage/rocksdb/third_party/lz4/ $PSDIR/storage/rocksdb/third_party/lz4 --exclude .git
    rsync -av storage/rocksdb/third_party/zstd/ $PSDIR/storage/rocksdb/third_party/zstd --exclude .git
    cd $PSDIR
    sed -i "1s/^/SET(TOKUDB_VERSION ${TOKUDB_VERSION})\n/" storage/tokudb/CMakeLists.txt
    sed -i "s:@@PERCONA_VERSION_EXTRA@@:${MYSQL_VERSION_EXTRA#-}:g" build-ps/debian/rules
    sed -i "s:@@REVISION@@:${REVISION}:g" build-ps/debian/rules
    sed -i "s:@@TOKUDB_BACKUP_VERSION@@:${TOKUDB_VERSION}:g" build-ps/debian/rules
    sed -i "s:@@PERCONA_VERSION_EXTRA@@:${MYSQL_VERSION_EXTRA#-}:g" build-ps/debian/rules.notokudb
    sed -i "s:@@REVISION@@:${REVISION}:g" build-ps/debian/rules.notokudb
    sed -i "s:@@PERCONA_VERSION_EXTRA@@:${MYSQL_VERSION_EXTRA#-}:g" build-ps/ubuntu/rules
    sed -i "s:@@REVISION@@:${REVISION}:g" build-ps/ubuntu/rules
    sed -i "s:@@TOKUDB_BACKUP_VERSION@@:${TOKUDB_VERSION}:g" build-ps/ubuntu/rules
    sed -i "s:@@PERCONA_VERSION_EXTRA@@:${MYSQL_VERSION_EXTRA#-}:g" build-ps/ubuntu/rules.notokudb
    sed -i "s:@@REVISION@@:${REVISION}:g" build-ps/ubuntu/rules.notokudb

    sed -i "s:@@MYSQL_VERSION@@:${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}.${MYSQL_VERSION_PATCH}:g" build-ps/percona-server.spec
    sed -i "s:@@PERCONA_VERSION@@:${MYSQL_VERSION_EXTRA#-}:g" build-ps/percona-server.spec
    sed -i "s:@@REVISION@@:${REVISION}:g" build-ps/percona-server.spec
    sed -i "s:@@RPM_RELEASE@@:${RPM_RELEASE}:g" build-ps/percona-server.spec
    sed -i "s:@@BOOST_PACKAGE_NAME@@:${BOOST_PACKAGE_NAME}:g" build-ps/percona-server.spec
    
    cd $WORKDIR/percona-server
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    tar --owner=0 --group=0 --exclude=.bzr --exclude=.git -czf $PSDIR.tar.gz $PSDIR
    cp $PSDIR.tar.gz $WORKDIR/source_tarball
    cp $PSDIR.tar.gz $CURDIR/source_tarball
    rm -fr $PSDIR
    return
}

get_system(){
    if [ -f /etc/redhat-release ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        OS_NAME="el$RHEL"
        OS="rpm"
    fi
    if [ -f /etc/lsb-release ]; then
        ARCH=$(uname -m)
        OS_NAME="$(lsb_release -sc)"
        OS="deb"
    fi
    return
}

fix_spec() {
    PATH_TO_SPEC=$1
    PATH_TO_VERSION=$2
    source $PATH_TO_VERSION
    link="https://github.com/percona/percona-server/blob/5.7/cmake/boost.cmake"
    if [ ! -z $BRANCH ]
    then
        link=$( echo $link | sed "s:5.7:$BRANCH:" )
    fi
    wget $link
    BOOST_PACKAGE_NAME=$(cat boost.cmake|grep "SET(BOOST_PACKAGE_NAME"|awk -F '"' '{print $2}')
    rm -f boost.cmake
    sed -i "s:@@MYSQL_VERSION@@:${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}.${MYSQL_VERSION_PATCH}:g" percona-server.spec
    sed -i "s:@@PERCONA_VERSION@@:${MYSQL_VERSION_EXTRA#-}:g" percona-server.spec
    sed -i "s:@@REVISION@@:${REVISION}:g" percona-server.spec
    sed -i "s:@@RPM_RELEASE@@:${RPM_RELEASE}:g" percona-server.spec
    sed -i "s:@@BOOST_PACKAGE_NAME@@:${BOOST_PACKAGE_NAME}:g" percona-server.spec  
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
    if [ "x$OS" = "xrpm" ]
    then
        add_percona_yum_repo
        yum -y install git wget
        yum -y install gcc-c++ epel-release rpmdevtools bison
        cd $WORKDIR
        link="https://raw.githubusercontent.com/percona/percona-server/5.7/build-ps/percona-server.spec"
        link_ver="https://raw.githubusercontent.com/percona/percona-server/5.7/VERSION"
        if [ ! -z $BRANCH ]
        then
            link=$( echo $link | sed "s:5.7:$BRANCH:g" )
            link_ver=$( echo $link_ver | sed "s:5.7:$BRANCH:g" )
        fi
        wget $link
        wget $link_ver
        fix_spec $WORKDIR/percona-server.spec $WORKDIR/VERSION
        if [ ${ARCH} = x86_64 -a ${RHEL} != 7 ]; then
            yum install -y percona-devtoolset-gcc percona-devtoolset-binutils percona-devtoolset-gcc-c++ percona-devtoolset-libstdc++-devel percona-devtoolset-valgrind-devel
        fi
        yum install -y http://www.percona.com/downloads/percona-release/redhat/0.1-4/percona-release-0.1-4.noarch.rpm
        yum install -y Percona-Server-server-55
        cd $CURPLACE
        yum-builddep -y $WORKDIR/percona-server.spec
    else
        add_percona_apt_repo
        apt-get update
        apt-get -y install devscripts equivs
        CURPLACE=$(pwd)
        cd $WORKDIR
        link="https://raw.githubusercontent.com/EvgeniyPatlan/percona-server/5.7/build-ps/debian/control"
        if [ ! -z $BRANCH ]
        then
            link=$( echo $link | sed "s:5.7:$BRANCH:" )
        fi
        wget $link
        cd $CURPLACE
        sed -i 's:apt-get :apt-get -y --force-yes :g' /usr/bin/mk-build-deps
        mk-build-deps --install $WORKDIR/control
    fi
    return;
}

get_tar(){
    TARFILE=$(basename $(find $WORKDIR -iname 'Percona-Server*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR -iname 'Percona-Server*.tar.gz' | sort | tail -n1))
        if [ -z $TARFILE ]
        then
            echo "There is no source tarball for build"
            echo "You can create it using key --get_sources=1"
            exit 1
        else
            cp $CURDIR/$TARFILE $WORKDIR
        fi
    fi
    return
}

get_deb_sources(){
    param=$1
    echo $param
    FILE=$(basename $(find $WORKDIR -iname "percona-server*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR -iname "percona-server.$param" | sort | tail -n1))
        if [ -z $FILE ]
        then
            echo "There is no source tarball for build"
            echo "You can create it using key --get_sources=1"
            exit 1
        else
            cp $CURDIR/$FILE $WORKDIR
        fi
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
    get_tar
    cd $WORKDIR
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    #
    cd $WORKDIR/rpmbuild/SPECS
    tar vxzf $WORKDIR/$TARFILE --wildcards '*/build-ps/*.spec' --strip=2
    #
    cd $WORKDIR/rpmbuild/SOURCES
    wget http://jenkins.percona.com/downloads/boost/${BOOST_PACKAGE_NAME}.tar.gz
    for f in '*/build-ps/rpm/*.patch' '*/build-ps/rpm/filter-provides.sh' '*/build-ps/rpm/filter-requires.sh' '*/build-ps/rpm/mysql_config.sh' '*/build-ps/rpm/my_config.h'
    do
        tar vxzf $WORKDIR/$TARFILE --wildcards $f --strip=3
    done
    #
    cd $WORKDIR
    #
    mv -fv $TARFILE $WORKDIR/rpmbuild/SOURCES
    #
    rpmbuild -bs --define "_topdir $WORKDIR/rpmbuild" --define "dist .generic" rpmbuild/SPECS/percona-server.spec
    cp $WORKDIR/rpmbuild/SRPMS/* $CURDIR
    cp $WORKDIR/rpmbuild/SRPMS/* $WORKDIR
    rm -rf $WORKDIR/rpmbuild
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
    SRC_RPM=$(basename $(find $WORKDIR -iname 'Percona-Server*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR -iname 'Percona-Server*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]
        then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
            exit 1
        else
            cp $CURDIR/$SRC_RPM $WORKDIR
        fi
    fi
    cd $WORKDIR
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    #
    mv *.src.rpm rpmbuild/SRPMS
    #
    if [ ${ARCH} = x86_64 ]; then
      if [ ${RHEL} != 7 ]; then
        source /opt/percona-devtoolset/enable
      fi
    fi
    # build mecab library
    build_mecab_lib_rhel
    #
    cd ${WORKDIR}
    #
    if [ ${ARCH} = x86_64 ]; then
      rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .el${RHEL}" --define "with_mecab ${MECAB_INSTALL_DIR}/usr" --rebuild rpmbuild/SRPMS/${SRC_RPM}
    else
      rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .el${RHEL}" --define "with_tokudb 0" --define "with_rocksdb 0" --define "with_mecab ${MECAB_INSTALL_DIR}/usr" --rebuild rpmbuild/SRPMS/${SRC_RPM}
    fi
}

build_source_deb(){
    if [ $SDEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    get_tar
    cd $WORKDIR
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2}')
    VERSION=$(echo ${TARFILE}| awk -F '-' '{print $3}')
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    TMPREL=$(echo ${TARFILE}| awk -F '-' '{print $4}')
    RELEASE=${TMPREL%.tar.gz}
    #
    rm -fr ${NAME}-${VERSION}-${RELEASE}
    #
    NEWTAR=${NAME}-${SHORTVER}_${VERSION}-${RELEASE}.orig.tar.gz
    mv ${TARFILE} ${NEWTAR}
    #
    tar xzf ${NEWTAR}
    cd ${NAME}-${VERSION}-${RELEASE}
    cp -ap build-ps/debian/ .
    dch -D unstable --force-distribution -v "${VERSION}-${RELEASE}-${DEB_RELEASE}" "Update to new upstream release Percona Server ${VERSION}-${RELEASE}-1"
    dpkg-buildpackage -S

    cd $WORKDIR
    cp *.dsc $WORKDIR
    cp *.orig.tar.gz $WORKDIR
    cp *.debian.tar.* $WORKDIR
    cp *.changes $WORKDIR
    cp *.dsc $CURDIR
    cp *.orig.tar.gz $CURDIR
    cp *.debian.tar.* $CURDIR
    cp *.changes $CURDIR
}

build_deb(){
    if [ $DEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    for file in 'dsc' 'orig.tar.gz' 'debian.tar.*' 'changes'
    do
        get_deb_sources $file
    done
    cd $WORKDIR  
    DEBIAN_VERSION="$(lsb_release -sc)"
    DSC=$(basename $(find . -name 'percona-xtrabackup*.dsc' | sort | tail -n 1))
    DIRNAME=$(echo $DSC | sed -e 's:_:-:g' | awk -F'-' '{print $1"-"$2"-"$3}')
    VERSION=$(echo $DSC | sed -e 's:_:-:g' | awk -F'-' '{print $4}' | awk -F'.' '{print $1}')
    ARCH=$(uname -m)
    dpkg-source -x $DSC
    cd $DIRNAME
    VER=$(echo $DIRNAME | sed -e 's:percona-xtrabackup-::')
    dch -m -D "$DEBIAN_VERSION" --force-distribution -v "$VER-$DEB_RELEASE.$DEBIAN_VERSION" 'Update distribution'
    dpkg-buildpackage -rfakeroot -uc -us -b
    #
    cd ${WORKDIR}
    #rm -fv *.dsc *.orig.tar.gz *.debian.tar.gz *.changes 
#    rm -fr ${DIRNAME}
}

build_tarball(){
    if [ $TARBALL = 0 ]
    then
        echo "Binary tarball will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" -o "x$RHEL" != "x6" ]
    then
        echo "It is not possible to build binary tarball here"
        exit 1
    fi
    get_tar
    cd $WORKDIR
    dirname=`tar -tzf $TARFILE | head -1 | cut -f1 -d"/"`
    tar xzf $TARFILE
    cd  $dirname
    mkdir $WORKDIR/BUILD_XYZ
    bash -x ./storage/innobase/xtrabackup/utils/build-binary.sh $WORKDIR/BUILD_XYZ
    cp $WORKDIR/BUILD_XYZ/percona-xtrabackup*.tar.gz $WORKDIR/
    cp $WORKDIR/BUILD_XYZ/percona-xtrabackup*.tar.gz $CURDIR/
    cd $CURDIR
}

build_mecab_lib_rhel(){
    rm -f $MECAB_TARBAL $MECAB_DIR $MECAB_INSTALL_DIR
    mkdir $MECAB_INSTALL_DIR
    wget $MECAB_LINK
    tar xf $MECAB_TARBAL
    cd  $MECAB_DIR
        ./configure --with-pic --prefix=/usr
        make
        make check
        make DESTDIR=$MECAB_INSTALL_DIR install
    cd ..
    rm -rf $MECAB_IPADIC_TARBAL $MECAB_IPADIC_DIR
    wget $MECAB_IPADIC_LINK
    tar xf $MECAB_IPADIC_TARBAL
    cd $MECAB_IPADIC_DIR
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$MECAB_INSTALL_DIR/usr/lib
        sed -i "/MECAB_DICT_INDEX=\"/c\MECAB_DICT_INDEX=\"$MECAB_INSTALL_DIR\/usr\/libexec\/mecab\/mecab-dict-index\"" configure
        ./configure --with-mecab-config=$MECAB_INSTALL_DIR/usr/bin/mecab-config
        make
        make DESTDIR=$MECAB_INSTALL_DIR install
    cd ../
    cd $MECAB_INSTALL_DIR
        if [ -d usr/lib64 ]; then
            mv usr/lib64/* usr/lib
        fi
    cd ../
}

parse_arguments PICK-ARGS-FROM-ARGV "$@"
check_workdir
MECAB_TARBAL="mecab-0.996.tar.gz"
MECAB_LINK="http://jenkins.percona.com/downloads/mecab/${MECAB_TARBAL}"
MECAB_DIR="${WORKDIR}/${MECAB_TARBAL%.tar.gz}"
MECAB_INSTALL_DIR="${WORKDIR}/mecab-install"
MECAB_IPADIC_TARBAL="mecab-ipadic-2.7.0-20070801.tar.gz"
MECAB_IPADIC_LINK="http://jenkins.percona.com/downloads/mecab/${MECAB_IPADIC_TARBAL}"
MECAB_IPADIC_DIR="${WORKDIR}/${MECAB_IPADIC_TARBAL%.tar.gz}"
get_system
install_deps
get_sources
build_srpm
build_source_deb
build_rpm
build_tarball
build_deb