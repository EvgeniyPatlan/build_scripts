library changelog: false, identifier: 'lib@master', retriever: modernSCM([
    $class: 'GitSCMSource',
    remote: 'https://github.com/EvgeniyPatlan/jenkins-pipelines.git'
]) _

pipeline {
    environment {
        specName = 'Docker'
    }
    agent {
        label 'min-jessie-x64'
    }
    parameters {
        choice(
            choices: 'percona-server\npercona-server.56\npercona-server-mongodb\npercona-server-mongodb.32\npercona-server-mongodb.34\npercona-server-mongodb.36\nproxysql\npxc-56\npxc-57',
            description: 'Select docker for build',
            name: 'DOCKER_NAME')
        string(
            defaultValue: 'master',
            description: 'Tag/Branch for percona-docker repository',
            name: 'GIT_BRANCH')
        string(
            defaultValue: 'https://github.com/percona/percona-docker.git',
            description: 'percona-docker repository',
            name: 'GIT_REPO')
    }
    options {
        skipDefaultCheckout()
        disableConcurrentBuilds()
    }

    stages {
        stage('Prepare') {
            steps {
                sh '''
                  rm -f docker_builder.sh; \
                  wget https://raw.githubusercontent.com/EvgeniyPatlan/build_scripts/master/docker/docker_builder.sh; \
                  chmod +x docker_builder.sh; \
                  sudo rm -rf docker_build; \
                  mkdir docker_build; \
                  sudo bash -x docker_builder.sh --builddir=$(pwd)/docker_build --build_docker=0 --save_docker=0 --docker_name=${DOCKER_NAME} --version=${PACKAGE} --clean_docker=0 --test_docker=0 --install_docker=1
                '''
            }
        }

        stage('Build Image') {
            steps {
                sh '''
                  sudo bash -x docker_builder.sh --builddir=$(pwd)/docker_build --build_docker=1 --save_docker=0 --docker_name=${DOCKER_NAME} --version=${PACKAGE} --clean_docker=1 --test_docker=0 --install_docker=0 --auto=1
                '''
            }
        }
        
        stage('Save Image') {
            steps {
                sh '''
                  sudo bash -x docker_builder.sh --builddir=$(pwd)/docker_build --build_docker=0 --save_docker=1 --docker_name=${DOCKER_NAME} --version=${PACKAGE} --clean_docker=0 --test_docker=0 --install_docker=0 --auto=1
                '''
            }
        }
        
        stage('Test Image') {
            steps {
                sh '''
                  TAR=$(ls $(pwd)/docker_build | grep tar); \
                  sudo bash -x docker_builder.sh --builddir=$(pwd)/docker_build --build_docker=0 --save_docker=0 --docker_name=${DOCKER_NAME} --version=${PACKAGE} --clean_docker=1 --test_docker=1 --install_docker=0 --auto=1 --load_docker=$(pwd)/docker_build/${TAR}; \
                  sudo cp $(pwd)/docker_build/${TAR} ./ ; \
                  sudo rm -rf $(pwd)/docker_build
                '''
                archiveArtifacts "*.tar.gz"
            }
        }
        

        stage('Upload') {
            steps {
                sh """
                    echo "HERE WE WILL UPLOAD IMAGE"
                """
            }
        }
    }

    post {
        always {
            deleteDir()
        }
    }
}
