# Confluent Kafka Packaging
#
# The 'master' branch contains a script for packaging a plain archive file,
# including a more standardized (i.e. non-Java project) layout. Other branches,
# e.g. 'debian' build on this basic functionality. In order to support
# traditional installation, a normal 'install' target is provided, and the
# default 'archive' target just compresses the target prefix directory. Note
# that for safety and testing, the default PREFIX is specified relative to the
# working directory.
#
# In order to use any of the branches, including this one, you must merge it
# with the Kafka code. We use this model since it makes packaging some
# distributions, such as debian, much simpler since the normally use
# overlay-based packaging. You should start by generating a new branch for the
# type of package and Kafka version you're releasing:
#
#     git checkout -b archive-0.8.2
#
# and then merge in the upstream tree, presumably a tagged version:
#
#     git merge 0.8.2
#
# and finally create the package:
#
#     make archive
#
# which will generate kafka-0.8.2.tar.gz in this case. Note that the version
# used in these scripts is determined automatically by looking at tags, so it is
# not affected by the branch name 'archive-0.8.2'; that name is purely for you
# to keep track of release branches. Since the branch is a simple merge, it can
# be discarded after generating the release.
#
# In order to be able to apply patches cleanly and repeatably, this script *will
# use git-reset to clean out any changes that aren't already committed to the
# tree*. You need to make sure the changes you want applied are either:
# a) in the Kafka source tree, b) committed to the archive packaging branch, or
# c) in the form of a patch in patches/ and listed in patches/series.
#
# Dependencies you'll probably need to install to compile this: make, curl, git,
# zip, unzip, patch, java7-jdk | openjdk-7-jdk.

GRADLE_VERSION=2.2.1
GRADLE=./gradle-$(GRADLE_VERSION)/bin/gradle

# Release specifics. Note that some of these (VERSION, SCALA_VERSION, DESTDIR)
# are required and passed to create_archive.sh as environment variables. That
# script can also pick up some other settings (PREFIX, SYSCONFDIR) to customize
# layout of the installation.
# Source version *must* be extracted from the source code since we need it to
# use files that are generated.
SOURCE_VERSION=$(shell grep version gradle.properties | awk -F= '{ print $$2 }')
# Version is our own packaged version number.
ifndef VERSION
ifeq ($(wildcard .git),.git)
tag=$(shell git describe --abbrev=0)
ver=$(shell echo $(tag) | sed -e 's/kafka-//' -e 's/-incubating-candidate-[0-9]//')
VERSION=$(ver)
else
VERSION=$(SOURCE_VERSION)
endif
endif

ifndef SCALA_VERSION
SCALA_VERSION=$(shell grep ext[.]scalaVersion scala.gradle | awk -F\' '{ print $$2 }')
endif
SCALA_VERSION_UNDERSCORE=$(subst .,_,$(SCALA_VERSION))

export PACKAGE_NAME=confluent-kafka-$(VERSION)-$(SCALA_VERSION)


# Defaults that are likely to vary by platform. These are cleanly separated so
# it should be easy to maintain altered values on platform-specific branches
# when the values aren't overridden by the script invoking the Makefile
DEFAULT_APPLY_PATCHES=yes
DEFAULT_DESTDIR=$(CURDIR)/BUILD/
DEFAULT_PREFIX=$(PACKAGE_NAME)
DEFAULT_SYSCONFDIR=PREFIX/etc/kafka
DEFAULT_INCLUDE_WINDOWS_BIN=yes
DEFAULT_PS_ENABLED=yes
DEFAULT_SKIP_TESTS=no


# Whether we should apply patches. This only makes sense for alternate packaging
# systems that know how to apply patches themselves, e.g. Debian.
ifndef APPLY_PATCHES
APPLY_PATCHES=$(DEFAULT_APPLY_PATCHES)
endif

# Whether we should run tests during the build.
ifndef SKIP_TESTS
SKIP_TESTS=$(DEFAULT_SKIP_TESTS)
endif

# Install directories
ifndef DESTDIR
DESTDIR=$(DEFAULT_DESTDIR)
endif
# For platform-specific packaging you'll want to override this to a normal
# PREFIX like /usr or /usr/local. Using the PACKAGE_NAME here makes the default
# zip/tgz files use a format like:
#   kafka-version-scalaversion/
#     bin/
#     etc/
#     share/kafka/
ifndef PREFIX
PREFIX=$(DEFAULT_PREFIX)
endif

ifndef SYSCONFDIR
SYSCONFDIR:=$(DEFAULT_SYSCONFDIR)
endif
SYSCONFDIR:=$(subst PREFIX,$(PREFIX),$(SYSCONFDIR))

ifndef INCLUDE_WINDOWS_BIN
INCLUDE_WINDOWS_BIN=$(DEFAULT_INCLUDE_WINDOWS_BIN)
endif

ifndef PS_ENABLED
PS_ENABLED=$(DEFAULT_PS_ENABLED)
endif

ifeq ($(PS_ENABLED),yes)
PATCH_SERIES_TEMPLATE=series.proactive_support.in
else
PATCH_SERIES_TEMPLATE=series.in
endif

export APPLY_PATCHES
export SOURCE_VERSION
export VERSION
export SCALA_VERSION
export DESTDIR
export PREFIX
export SYSCONFDIR
export INCLUDE_WINDOWS_BIN
export PS_ENABLED
export PS_PACKAGES
export PS_CLIENT_PACKAGE
export CONFLUENT_VERSION
export SKIP_TESTS

all: install


archive: install
	rm -f $(CURDIR)/$(PACKAGE_NAME).tar.gz && cd $(DESTDIR) && tar -czf $(CURDIR)/$(PACKAGE_NAME).tar.gz $(PREFIX)
	rm -f $(CURDIR)/$(PACKAGE_NAME).zip && cd $(DESTDIR) && zip -r $(CURDIR)/$(PACKAGE_NAME).zip $(PREFIX)

gradle: gradle-$(GRADLE_VERSION)

gradle-$(GRADLE_VERSION):
	cp /tmp/gradle-$(GRADLE_VERSION)-bin.zip . || (curl -O -L "https://s3-us-west-2.amazonaws.com/confluent-packaging-tools/gradle-$(GRADLE_VERSION)-bin.zip" && cp gradle-$(GRADLE_VERSION)-bin.zip /tmp)
	unzip gradle-$(GRADLE_VERSION)-bin.zip
	rm -rf gradle-$(GRADLE_VERSION)-bin.zip

apply-patches: $(wildcard patches/*)
ifeq ($(APPLY_PATCHES),yes)
	git reset --hard HEAD
	cat patches/series | xargs -IPATCH bash -c 'patch -p1 < patches/PATCH'
endif

kafka: gradle apply-patches
	$(GRADLE) -PscalaVersion=$(SCALA_VERSION)
	./gradlew -PscalaVersion=$(SCALA_VERSION) install
	./gradlew -PscalaVersion=$(SCALA_VERSION) releaseTarGz_$(SCALA_VERSION_UNDERSCORE)

# create_archive gets the
install: kafka
	./create_archive.sh

clean:
	rm -rf $(CURDIR)/gradle-*
	rm -rf $(DESTDIR)$(PREFIX)
	rm -rf $(CURDIR)/$(PACKAGE_NAME)*

distclean: clean
	git reset --hard HEAD
	git status --ignored --porcelain | cut -d ' ' -f 2 | xargs rm -rf

test:

.PHONY: clean install

patch-series:
	cp patches/$(PATCH_SERIES_TEMPLATE) patches/series
	git add patches/series
	git commit -m "Created patches/series"
