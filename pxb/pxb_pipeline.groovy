void build_src_rpm(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'source_tarball'
        sh """
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/pxb_builder.sh
            rm -rf pxb_${BRANCH}
            mkdir  pxb_${BRANCH}
            sh -x pxb_builder.sh --builddir=\$(pwd)/pxb_${BRANCH} --build_src_rpm=1 --branch=${BRANCH}
            rm -rf pxb_builder.sh 
        """
        archiveArtifacts "*.src.rpm"
        stash includes: '*.src.rpm', name: 'srpm'
    }
}

void build_tarball(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'source_tarball'
        sh '''
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/pxb_builder.sh; \
            rm -rf pxb_${BRANCH}; \
            mkdir pxb_${BRANCH}; \
            sudo sh -x pxb_builder.sh --builddir=$(pwd)/pxb_${BRANCH} --install_deps=1; \
            sh -x pxb_builder.sh --builddir=$(pwd)/pxb_${BRANCH} --build_tarball=1 --branch=${BRANCH}; \
            rm -rf pxb_builder.sh 
        '''
        archiveArtifacts "*.tar.gz"
        stash includes: '*.tar.gz', name: 'tar'
    }
}

void build_rpm(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'srpm'
        sh '''
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/pxb_builder.sh; \
            rm -rf pxb_${BRANCH}; \
            mkdir pxb_${BRANCH}; \
            sudo sh -x pxb_builder.sh --builddir=$(pwd)/pxb_${BRANCH} --install_deps=1; \
            sh -x pxb_builder.sh --builddir=$(pwd)/pxb_${BRANCH} --build_rpm=1 --branch=${BRANCH}; \
            rm -rf pxb_builder.sh 
        '''
        archiveArtifacts "*.rpm"
        stash includes: '*.rpm', name: 'rpm'
    }
}

void build_source_deb(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'source_tarball'
        sh """
            rm -rf percona-xtrabackup; \
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/pxb_builder.sh
            rm -rf pxb_${BRANCH}
            mkdir  pxb_${BRANCH}
            sh -x pxb_builder.sh --builddir=\$(pwd)/pxb_${BRANCH} --build_source_deb=1 --branch=${BRANCH}
            rm -rf pxb_builder.sh 
        """
        archiveArtifacts "percona-xtrabackup*"
        stash includes: 'percona-xtrabackup*', name: 'sdeb'
    }
}

void build_deb(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'sdeb'
        sh '''
            rm -rf percona-xtrabackup; \
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/pxb_builder.sh; \
            rm -rf pxb_${BRANCH}; \
            mkdir pxb_${BRANCH}; \
            sudo sh -x pxb_builder.sh --builddir=$(pwd)/pxb_${BRANCH} --install_deps=1; \
            sh -x pxb_builder.sh --builddir=$(pwd)/pxb_${BRANCH} --build_deb=1 --branch=${BRANCH}; \
            cp pxb_${BRANCH}/*.deb . ;\
            ls ;\
            rm -rf pxb_builder.sh 
        '''
        archiveArtifacts "*.deb"
        stash includes: '*.deb', name: 'deb'
    }
}


pipeline {
    agent {
        label 'master'
    }
    parameters {
        string(
            defaultValue: 'git://github.com/percona/percona-xtrabackup.git',
            description: 'GIT REPO',
            name: 'GIT_REPO')
        string(
            defaultValue: '2.4',
            description: 'GIT BRANCH',
            name: 'BRANCH')
        string(
            defaultValue: '1',
            description: 'RPM VERSION',
            name: 'RPM_RELEASE')
        string(
            defaultValue: '1',
            description: 'DEB VERSION',
            name: 'DEB_RELEASE')
    }
    options {
        skipDefaultCheckout()
        disableConcurrentBuilds()
    }

    stages {
        stage('Fetch sources') {
            steps {
                sh '''
                   wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/pxb_builder.sh; \
                   rm -rf pxb_${BRANCH}; \
                   mkdir pxb_${BRANCH}; \
                   sh -x pxb_builder.sh --builddir=$(pwd)/pxb_${BRANCH} --get_sources=1 --branch=${BRANCH}; \
                   rm -rf pxb_builder.sh 
                '''
                archiveArtifacts "*.tar.gz"
                stash includes: '*.tar.gz', name: 'source_tarball'
            }
        }
        stage('Build Sources') {
            steps {
                parallel(
                    "centos6-64": {
                        build_src_rpm('centos6-64')
                    },
                    "debian-wheezy-x64": {
                        build_source_deb('debian-wheezy-x64')
                    }
               )
            }
        }
        stage('Build Packages') {
            steps {
                parallel(
                    "centos6-64": {
                        build_rpm('centos6-64')
                    },
                    "centos7-64": {
                        build_rpm('centos7-64')
                    },
                    "centos6-32": {
                        build_rpm('centos6-32')
                    },
                    "debian-wheezy-x64": {
                        build_deb('debian-wheezy-x64')
                    },
                    "debian-wheezy-x32": {
                        build_deb('debian-wheezy-x32')
                    },
                    "debian-jessie-64bit": {
                        build_deb('debian-jessie-64bit')
                    },
                    "debian-jessie-32bit": {
                        build_deb('debian-jessie-32bit')
                    },
                    "debian-stretch-64bit": {
                        build_deb('debian-stretch-64bit')
                    },
                    "ubuntu-trusty-64bit": {
                        build_deb('ubuntu-trusty-64bit')
                    },
                    "ubuntu-trusty-32bit": {
                        build_deb('ubuntu-trusty-32bit')
                    },
                    "ubuntu-xenial-64bit": {
                        build_deb('ubuntu-xenial-64bit')
                    },
                    "ubuntu-xenial-32bit": {
                        build_deb('ubuntu-xenial-32bit')
                    },
                    "ubuntu-yakkety-64bit": {
                        build_deb('ubuntu-yakkety-64bit')
                    },
                    "ubuntu-yakkety-32bit": {
                        build_deb('ubuntu-yakkety-32bit')
                    },
                    "ubuntu-zesty-64bit": {
                        build_deb('ubuntu-zesty-64bit')
                    },
                    "ubuntu-zesty-32bit": {
                        build_deb('ubuntu-zesty-32bit')
                    },
               )
            }
        }
        stage('Build Tarballs') {
            steps {
                parallel(
                    "centos6-64": {
                        build_tarball('centos6-64')
                    },
                    "centos6-32": {
                        build_tarball('centos6-32')
                    },
                    "debian-wheezy-x64": {
                        build_tarball('debian-wheezy-x64')
                    },
                    "debian-wheezy-x32": {
                        build_tarball('debian-wheezy-x32')
                    },
               )
            }
        }
    }
}
