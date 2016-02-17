#!/bin/bash
#
# Creates an archive suitable for distribution (standard layout for binaries,
# libraries, etc.) from a release archive. Assumes that .

set -e

if [ -z "${VERSION}" -o -z "${SOURCE_VERSION}" -o -z "${SCALA_VERSION}" -o -z "${DESTDIR}" -o -z "${PS_PACKAGES}" -o -z "$PS_CLIENT_PACKAGE" -o -z "${CONFLUENT_VERSION}" -o -z "${SKIP_TESTS}" ]; then
    echo "VERSION, SOURCE_VERSION, SCALA_VERSION, DESTDIR, PS_PACKAGES, PS_CLIENT_PACKAGE, CONFLUENT_VERSION, and SKIP_TESTS environment variables must be set."
    exit 1
fi

if [ -z ${SYSCONFDIR} ]; then
    SYSCONFDIR="${PREFIX}/etc/kafka"
fi

if `echo ${SCALA_VERSION} | grep '^2[.]8[.]' >/dev/null` || `echo ${SCALA_VERSION} | grep '^2[.]9[.]' >/dev/null`; then
    SCALA_VERSION_SHORT=${SCALA_VERSION}
else
    SCALA_VERSION_SHORT=`echo ${SCALA_VERSION} | awk -F. '{print $1"."$2}'`
fi

BINPATH=${PREFIX}/bin
LIBPATH=${PREFIX}/share/java/kafka
DOCPATH=${PREFIX}/share/doc/kafka

INSTALL="install -D -m 644"
INSTALL_X="install -D -m 755"
TMP_ARCHIVE_PATH="kafka_archive_tmp"

rm -rf ${DESTDIR}${PREFIX}
mkdir -p ${DESTDIR}${PREFIX}
mkdir -p ${DESTDIR}${BINPATH}
mkdir -p ${DESTDIR}${LIBPATH}
mkdir -p ${DESTDIR}${DOCPATH}
mkdir -p ${DESTDIR}${SYSCONFDIR}

###
### Build and integrate Proactive Support into Kafka's eventual package
###
### Note: Proactive Support depends on Kafka, therefore we ran the builds
###       at a point where Kafka itself was already built (cf. Makefile)
###       and is now available in a local maven repository.
if [ "$PS_ENABLED" = "yes" ]; then
  BUILDROOT=/tmp/confluent
  for PS_PKG in $PS_PACKAGES; do
    pushd $BUILDROOT/$PS_PKG
    if [ "$SKIP_TESTS" = "yes" ]; then
      mvn -DskipTests=true clean install package
    else
      mvn clean install package
    fi
    PS_DOCPATH_RELATIVE=share/doc/confluent-${PS_PKG}
    mkdir -p ${DESTDIR}${PREFIX}/${PS_DOCPATH_RELATIVE}
    ${INSTALL} -o root -g root ${BUILDROOT}/$PS_PKG/package/target/${PS_PKG}-package-*-package/${PS_DOCPATH_RELATIVE}/LICENSE* ${DESTDIR}${PREFIX}/${PS_DOCPATH_RELATIVE}/
    ${INSTALL} -o root -g root ${BUILDROOT}/$PS_PKG/package/target/${PS_PKG}-package-*-package/${PS_DOCPATH_RELATIVE}/NOTICE*  ${DESTDIR}${PREFIX}/${PS_DOCPATH_RELATIVE}/
    popd
  done
  BUILD_PACKAGE_ROOT=`find $BUILDROOT/$PS_CLIENT_PACKAGE/package/target -maxdepth 1 -name "${PS_CLIENT_PACKAGE}-package-*-package" -type d | head -1`
  ${INSTALL_X} -o root -g root ${BUILD_PACKAGE_ROOT}/bin/* ${DESTDIR}${BINPATH}/
  for jardir in "$BUILD_PACKAGE_ROOT/share/java/*"; do
    ${INSTALL} -o root -g root ${jardir}/* ${DESTDIR}${LIBPATH}/
  done
fi

###
### Kafka
###
rm -rf ${TMP_ARCHIVE_PATH}
mkdir -p ${TMP_ARCHIVE_PATH}
tar -xf core/build/distributions/kafka_${SCALA_VERSION_SHORT}-${SOURCE_VERSION}.tgz -C ${TMP_ARCHIVE_PATH} --strip-components 1

${INSTALL_X} -o root -g root ${TMP_ARCHIVE_PATH}/bin/connect-* ${DESTDIR}${BINPATH}/
${INSTALL_X} -o root -g root ${TMP_ARCHIVE_PATH}/bin/kafka-* ${DESTDIR}${BINPATH}/
${INSTALL_X} -o root -g root ${TMP_ARCHIVE_PATH}/bin/zookeeper-* ${DESTDIR}${BINPATH}/
if [ "${INCLUDE_WINDOWS_BIN}" == "yes" ]; then
    mkdir -p ${DESTDIR}${BINPATH}/windows
    ${INSTALL_X} -o root -g root ${TMP_ARCHIVE_PATH}/bin/windows/*.bat ${DESTDIR}${BINPATH}/windows/
fi
${INSTALL} -o root -g root ${TMP_ARCHIVE_PATH}/libs/* ${DESTDIR}${LIBPATH}/
for path in ${TMP_ARCHIVE_PATH}/config/*; do
    ${INSTALL} -o root -g root ${path} ${DESTDIR}${SYSCONFDIR}/`basename ${path}`
done

${INSTALL} -o root -g root ${TMP_ARCHIVE_PATH}/LICENSE* ${DESTDIR}${DOCPATH}/
${INSTALL} -o root -g root ${TMP_ARCHIVE_PATH}/NOTICE* ${DESTDIR}${DOCPATH}/

ln -s ./kafka_${SCALA_VERSION_SHORT}-${SOURCE_VERSION}.jar ${DESTDIR}${LIBPATH}/kafka.jar # symlink for unversioned access to jar

${INSTALL} -o root -g root ${TMP_ARCHIVE_PATH}/libs/kafka-clients-${SOURCE_VERSION}.jar ${DESTDIR}${LIBPATH}/

rm -rf ${TMP_ARCHIVE_PATH}
