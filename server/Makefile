SHELL := bash

.PHONY: all
all: out/shalland

.PHONY: always-rebuild

# Avoid overwriting out/version unless it's actually changed, so as to
# avoid invalidating downstream artifacts.
out/version: out always-rebuild
	@git describe --tags HEAD > out/version.tmp
	@diff -q out/version out/version.tmp &>/dev/null || mv out/version.tmp out/version
	@rm -f out/version.tmp

.PHONY: run
run: out/shalland
	out/shalland --host=localhost --port=4381 --database out/library.sqlite3

.PHONY: watch
watch:
	watchexec -e go -r -n make run

out:
	mkdir -p out

src/version/generated.go: out/version
	go generate ./src/version

out/shalland: out src/version/generated.go $(shell find src)
	go build -o out/shalland ./src

VALID_OS_ARCH = @echo "$*" | grep -Eq "^[^-]+-[^-]+$$" || (echo "malformed os-arch pair: $*"; exit 1)
OS = $(word 1,$(subst -, ,$*))
ARCH = $(word 2,$(subst -, ,$*))

VALID_ARCH = @echo "$*" | grep -Eq "^[^-]+$$" || (echo "malformed arch: $*"; exit 1)

fake-%:
	$(VALID_OS_ARCH)
	@echo "GOOS=$(OS) GOARCH=$(ARCH)"

# Architectures:
out/shalland-%: out $(shell find src)
	$(VALID_OS_ARCH)
	GOOS=$(OS) GOARCH=$(ARCH) go build -o out/shalland-$* ./src

out/shalland-%.deb: out/version out/shalland-linux-% $(shell find packaging)
	$(VALID_ARCH)
	ARCH=$* ./packaging/build_deb.bash
