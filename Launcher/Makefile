# Launcher - Build

.PHONY: all build dylib cli clean test native

BUILD_DIR = .build/release
DYLIB = $(BUILD_DIR)/libLauncher.dylib
NATIVE_DIR = native-build
NATIVE_LIB = $(NATIVE_DIR)/libLauncher.dylib

# Detect architecture
ARCH := $(shell uname -m)
ifeq ($(ARCH),arm64)
	ARCH_FLAGS = -arch arm64
else
	ARCH_FLAGS = -arch x86_64
endif

CFLAGS = -O2 -fPIC $(ARCH_FLAGS) \
	-mmacosx-version-min=12.0 \
	-fobjc-arc \
	-framework AppKit \
	-framework Foundation \
	-framework QuartzCore

all: dylib cli native

# Build release
build:
	swift build -c release

# Build dynamic library for FFI
dylib: build
	@echo "✓ Built: $(DYLIB)"

# Build CLI tool
cli: build
	@echo "✓ Built: $(BUILD_DIR)/launcher-cli"

# Run CLI
run: cli
	$(BUILD_DIR)/launcher-cli

# Build native dylib for Bun FFI
$(NATIVE_DIR):
	mkdir -p $(NATIVE_DIR)

native: | $(NATIVE_DIR)
	clang -shared -o $(NATIVE_LIB) \
		$(CFLAGS) \
		src/launcher_ffi.m
	@echo "✓ Built: $(NATIVE_LIB)"

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build native-build

# Run tests
test:
	swift test

# Install CLI to ~/bin
install: cli
	mkdir -p ~/bin
	cp $(BUILD_DIR)/launcher-cli ~/bin/
	@echo "✓ Installed to ~/bin/launcher-cli"
