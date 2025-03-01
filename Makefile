# This Makefile is intended for developer convenience.  For the most part
# all the targets here simply wrap calls to the `cargo` tool.  Therefore,
# most targets must be marked 'PHONY' to prevent `make` getting in the way
#
#prog :=xnixperms

DESTDIR ?=
PREFIX ?= /usr/local
LIBEXECDIR ?= ${PREFIX}/libexec
LIBEXECPODMAN ?= ${LIBEXECDIR}/podman

SELINUXOPT ?= $(shell test -x /usr/sbin/selinuxenabled && selinuxenabled && echo -Z)

# Set this to any non-empty string to enable unoptimized
# build w/ debugging features.
debug ?=

# All complication artifacts, including dependencies and intermediates
# will be stored here, for all architectures.  Use a non-default name
# since the (default) 'target' is used/referenced ambiguously in many
# places in the tool-chain (including 'make' itself).
CARGO_TARGET_DIR ?= targets
export CARGO_TARGET_DIR  # 'cargo' is sensitive to this env. var. value.

ifdef debug
$(info debug is $(debug))
  # These affect both $(CARGO_TARGET_DIR) layout and contents
  # Ref: https://doc.rust-lang.org/cargo/guide/build-cache.html
  release :=
  profile :=debug
else
  release :=--release
  profile :=release
endif

.PHONY: all
all: build

bin:
	mkdir -p $@

$(CARGO_TARGET_DIR):
	mkdir -p $@

.PHONY: build
build: bin $(CARGO_TARGET_DIR)
	cargo build $(release)
	cp $(CARGO_TARGET_DIR)/$(profile)/aardvark-dns bin/aardvark-dns$(if $(debug),.debug,)

.PHONY: clean
clean:
	rm -rf bin
	if [ "$(CARGO_TARGET_DIR)" = "targets" ]; then rm -rf targets; fi
	$(MAKE) -C docs clean

#.PHONY: docs
#docs: ## build the docs on the host
#	$(MAKE) -C docs

.PHONY: install
install:
	install ${SELINUXOPT} -D -m0755 bin/aardvark-dns $(DESTDIR)/$(LIBEXECPODMAN)/aardvark-dns
	#$(MAKE) -C docs install

.PHONY: uninstall
uninstall:
	rm -f $(DESTDIR)/$(LIBEXECPODMAN)/aardvark-dns
	rm -f $(PREFIX)/share/man/man1/aardvark-dns*.1

#.PHONY: test
test: unit integration

# Used by CI to compile the unit tests but not run them
.PHONY: build_unit
build_unit: $(CARGO_TARGET_DIR)
	cargo test --no-run

#.PHONY: unit
unit: $(CARGO_TARGET_DIR)
	cargo test

#.PHONY: code_coverage
# Can be used by CI and users to generate code coverage report based on aardvark unit tests
code_coverage: $(CARGO_TARGET_DIR)
	# Downloads tarpaulin only if same version is not present on local
	cargo install cargo-tarpaulin
	cargo tarpaulin -v

#.PHONY: integration
integration: $(CARGO_TARGET_DIR)
	# needs to be run as root or with podman unshare --rootless-netns
	bats test/

.PHONY: mock-rpm
mock-rpm:
	rpkg local

.PHONY: validate
validate: $(CARGO_TARGET_DIR)
	cargo fmt --all -- --check
	cargo clippy -p aardvark-dns -- -D warnings

.PHONY: vendor-tarball
vendor-tarball: build install.cargo-vendor-filterer
	VERSION=$(shell bin/aardvark-dns --version | cut -f2 -d" ") && \
	cargo vendor-filterer '--platform=*-unknown-linux-*' --format=tar.gz --prefix vendor/ && \
	mv vendor.tar.gz aardvark-dns-v$$VERSION-vendor.tar.gz && \
	gzip -c bin/aardvark-dns > aardvark-dns.gz && \
	sha256sum aardvark-dns.gz aardvark-dns-v$$VERSION-vendor.tar.gz > sha256sum

.PHONY: install.cargo-vendor-filterer
install.cargo-vendor-filterer:
	cargo install cargo-vendor-filterer

.PHONY: help
help:
	@echo "usage: make $(prog) [debug=1]"
