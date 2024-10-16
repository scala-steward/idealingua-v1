#!/usr/bin/env bash
set -xe

# `++ 2.13.0 compile` has a different semantic than `;++2.13.0;compile`
# Strict aggregation applies ONLY to former, and ONLY if crossScalaVersions := Nil in root project
# see https://github.com/sbt/sbt/issues/3698#issuecomment-475955454
# and https://github.com/sbt/sbt/pull/3995/files
# TL;DR strict aggregation in sbt is broken; this is a workaround

SONATYPE_SECRET=.secrets/credentials.sonatype-nexus.properties

function scala3 {
  echo "Using Scala 3..."
  VERSION_COMMAND="++ $SCALA3"
}

function scala213 {
  echo "Using Scala 2.13..."
  VERSION_COMMAND="++ $SCALA213"
}

function scala212 {
  echo "Using Scala 2.12..."
  VERSION_COMMAND="++ $SCALA212"
}

function csbt {
  COMMAND="time sbt -batch -no-colors -v $*"
  eval $COMMAND
}

function coverage {
  csbt clean coverage "'$VERSION_COMMAND test'" "'$VERSION_COMMAND coverageReport'" || exit 1
}

function publishIDL {
  #copypaste
  if [[ "$CI_PULL_REQUEST" != "false"  ]] ; then
    return 0
  fi

  if [[ ! ("$CI_BRANCH" == "develop" || "$CI_BRANCH_TAG" =~ ^v.*$ ) ]] ; then
    return 0
  fi
  #copypaste

  if [[ -z "$NPM_TOKEN" ]] ; then
    return 0
  fi

  if [[ -z "$NUGET_TOKEN" ]] ; then
    return 0
  fi

  echo "PUBLISH IDL RUNTIMES..."

  echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" > ~/.npmrc
  npm whoami

  ./idealingua-v1/idealingua-v1-runtime-rpc-typescript/src/npmjs/publish.sh || exit 1
  ./idealingua-v1/idealingua-v1-runtime-rpc-csharp/src/main/nuget/publish.sh || exit 1
}

function publishScala {
  #copypaste
  if [[ "$CI_PULL_REQUEST" != "false"  ]] ; then
    return 0
  fi

  if [[ ! -f .secrets/credentials.sonatype-nexus.properties ]] ; then
    return 0
  fi

  if [[ ! ("$CI_BRANCH" == "develop" || "$CI_BRANCH_TAG" =~ ^v.*$ ) ]] ; then
    return 0
  fi

  echo "PUBLISH SCALA LIBRARIES..."

  if [[ "$CI_BRANCH" == "develop" ]] ; then
    csbt "'$VERSION_COMMAND clean'" "'$VERSION_COMMAND package'" "'$VERSION_COMMAND publishSigned'" || exit 1
  else
    csbt "'$VERSION_COMMAND clean'" "'$VERSION_COMMAND package'" "'$VERSION_COMMAND publishSigned'" sonatypeBundleRelease || exit 1
  fi
}

function init {
    export NPM_TOKEN=${TOKEN_NPM}
    export NUGET_TOKEN=${TOKEN_NUGET}

    export IZUMI_VERSION=$(cat version.sbt | sed -r 's/.*\"(.*)\".**/\1/' | sed -E "s/SNAPSHOT/build."${CI_BUILD_UNIQ_SUFFIX}"/")
    export SCALA212=$(cat project/Deps.sc | grep 'val scala212 ' |  sed -r 's/.*\"(.*)\".**/\1/')
    export SCALA213=$(cat project/Deps.sc | grep 'val scala213 ' |  sed -r 's/.*\"(.*)\".**/\1/')
    export SCALA3=$(cat project/Deps.sc | grep 'val scala300 ' |  sed -r 's/.*\"(.*)\".**/\1/')

    printenv
}

function secrets {
    if [[ "$CI_PULL_REQUEST" == "false"  ]] ; then
        mkdir .secrets
        echo "$SONATYPE_CREDENTIALS_FILE" > "$SONATYPE_SECRET"
        openssl aes-256-cbc -K ${OPENSSL_KEY} -iv ${OPENSSL_IV} -in secrets.tar.enc -out secrets.tar -d
        tar xvf secrets.tar
    fi
}

init


for i in "$@"
do
case $i in
    nothing)
        echo "Doing nothing..."
    ;;

    2.13)
        scala213
    ;;

    2.12)
        scala212
    ;;

    3*)
        scala3
    ;;

    coverage)
        coverage
    ;;

    publishIDL)
        publishIDL
    ;;

    publishScala)
        publishScala
    ;;

    sonatypeRelease)
        sonatypeRelease
    ;;

    secrets)
        secrets
    ;;

    *)
        echo "Unknown option: ${i}"
        exit 1
    ;;
esac
done
