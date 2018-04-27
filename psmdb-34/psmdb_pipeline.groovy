void build_src_rpm(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'source_tarball'
        sh '''
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/psmdb-34/psmdb_builder.sh
            sudo rm -rf psmdb
            mkdir  psmdb
            sudo bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --install_deps=1\
            bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --build_src_rpm=1
            rm -rf psmdb_builder.sh 
        '''
        archiveArtifacts "srpm/*.src.rpm"
        stash includes: 'srpm/*.src.rpm', name: 'srpm'
    }
}

void build_tarball(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'source_tarball'
        sh '''
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/psmdb-34/psmdb_builder.sh; \
            sudo rm -rf psmdb; \
            mkdir psmdb; \
            sudo bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --install_deps=1\
            bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --build_tarball=1 \
            rm -rf psmdb_builder.sh 
        '''
        archiveArtifacts "tarball/*.tar.gz"
        stash includes: 'tarball/*.tar.gz', name: 'tar'
    }
}

void build_debug_tarball(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'source_tarball'
        sh '''
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/psmdb-34/psmdb_builder.sh; \
            sudo rm -rf psmdb; \
            mkdir psmdb; \
            sudo bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --install_deps=1\
            bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --debug=1 \
            rm -rf psmdb_builder.sh 
        '''
        archiveArtifacts "debug/*.tar.gz"
        stash includes: 'debug/*.tar.gz', name: 'tar'
    }
}

void build_rpm(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'srpm'
        sh '''
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/psmdb-34/psmdb_builder.sh; \
            sudo rm -rf psmdb; \
            mkdir psmdb; \
            sudo bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --install_deps=1\
            bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --build_rpm=1
            rm -rf psmdb_builder.sh 
        '''
        archiveArtifacts "rpm/*.rpm"
        stash includes: 'rpm/*.rpm', name: 'rpm'
    }
}

void build_source_deb(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'source_tarball'
        sh '''
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/psmdb-34/psmdb_builder.sh
            sudo rm -rf psmdb
            mkdir  psmdb
            sudo bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --install_deps=1\
            bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --build_source_deb=1
            rm -rf psmdb_builder.sh 
        '''
        archiveArtifacts "source_deb/*"
        stash includes: 'source_deb/percona-server-mongodb-34*', name: 'sdeb'
    }
}

void build_deb(String NODE_LABEL) {
    node (NODE_LABEL) {
        unstash 'sdeb'
        sh '''
            wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/psmdb-34/psmdb_builder.sh; \
            sudo rm -rf psmdb; \
            mkdir psmdb; \
            sudo bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --install_deps=1\
            bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=$BRANCH_NAME --build_deb=1 \
            rm -rf psmdb_builder.sh 
        '''
        archiveArtifacts "deb/*.deb"
        stash includes: 'deb/*.deb', name: 'deb'
    }
}


pipeline {
    agent {
        label 'source-builder'
    }
    parameters {
        string(
            defaultValue: '3.4.14',
            description: 'PSM_VER',
            name: 'PSM_VER')
        string(
            defaultValue: '2.12',
            description: 'PSM_RELEASE',
            name: 'PSM_RELEASE')
        string(
            defaultValue: 'v3.4',
            description: 'PSM_BRANCH',
            name: 'PSM_BRANCH')
        string(
            defaultValue: 'r3.4.14',
            description: 'MONGO_TOOLS_TAG',
            name: 'MONGO_TOOLS_TAG')
            string(
            defaultValue: 'psmdb-3.2.11-3.1',
            description: 'JEMALLOC_TAG',
            name: 'JEMALLOC_TAG')
        string(
            defaultValue: 'v5.7.3',
            description: 'ROCKSDB_TAG',
            name: 'ROCKSDB_TAG')
    }
    options {
        skipDefaultCheckout()
        disableConcurrentBuilds()
    }

    stages {
        stage('Fetch sources') {
            steps {
                sh '''
                   wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/psmdb-34/psmdb_builder.sh; \
                   sudo rm -rf psmdb; \
                   mkdir psmdb; \
                   bash -x psmdb_builder.sh --builddir=$(pwd)/psmdb --branch=${PSM_BRANCH} --psm_ver=${PSM_VER} --psm_release=${PSM_RELEASE} --mongo_tools_tag=${MONGO_TOOLS_TAG} --ftindex_tag=${FTINDEX_TAG} --jemalloc_tag=${JEMALLOC_TAG} --rocksdb_tag=${ROCKSDB_TAG} --tokubackup_branch=${TOKUBACKUP_BRANCH} --get_sources=1 \
                   rm -rf psmdb_builder.sh 
                '''
                archiveArtifacts "source_tarball/*.tar.gz"
                stash includes: 'source_tarball/*.tar.gz', name: 'source_tarball'
            }
        }
        stage('Build Sources') {
            steps {
                parallel(
                    "min-centos-6-x64": {
                        build_src_rpm('min-centos-6-x64')
                    },
                    "min-trusty-x64": {
                        build_source_deb('min-trusty-x64')
                    }
               )
            }
        }
        stage('Build Packages') {
            steps {
                parallel(
                    "min-centos-6-x64": {
                        build_rpm('min-centos-6-x64')
                    },
                    "min-centos-7-x64": {
                        build_rpm('min-centos-7-x64')
                    },
                    "min-wheezy-x64": {
                        build_deb('min-wheezy-x64')
                    },
                    "min-jessie-x64": {
                        build_deb('min-jessie-x64')
                    },
                    "min-stretch-x64": {
                        build_deb('min-stretch-x64')
                    },
                    "min-trusty-x64": {
                        build_deb('min-trusty-x64')
                    },
                    "min-xenial-x64": {
                        build_deb('min-xenial-x64')
                    },
                    "min-artful-x64": {
                        build_deb('min-artful-x64')
                    },
                    "min-bionic-x64": {
                        build_deb('min-bionic-x64')
                    },
               )
            }
        }
        stage('Build Tarballs') {
            steps {
                parallel(
                    "min-centos-6-x64": {
                        build_tarball('min-centos-6-x64')
                    },
                    "min-centos-7-x64": {
                        build_tarball('min-centos-7-x64')
                    },
                    "debian-trusty-x64": {
                        build_tarball('debian-trusty-x64')
                    },
                    "debian-jessie-x64": {
                        build_tarball('debian-jessie-x64')
                    },
                    "debian-xenial-x64": {
                        build_tarball('debian-xenial-x64')
                    },
               )
            }
        }
        stage('Build Debug Tarballs') {
            steps {
                parallel(
                    "min-centos-6-x64": {
                        build_debug_tarball('min-centos-6-x64')
                    },
                    "min-centos-7-x64": {
                        build_debug_tarball('min-centos-7-x64')
                    },
                    "debian-trusty-x64": {
                        build_debug_tarball('debian-trusty-x64')
                    },
                    "debian-jessie-x64": {
                        build_debug_tarball('debian-jessie-x64')
                    },
                    "debian-xenial-x64": {
                        build_debug_tarball('debian-xenial-x64')
                    },
               )
            }
        }
    }
}
