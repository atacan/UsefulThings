.PHONY: all build build-macos build-ios clean test help

# Default target - build for both platforms
all: build

# Build for both platforms
build: build-macos build-ios
	@echo "✓ Successfully built for all platforms"

# Build for macOS
build-macos:
	@echo "Building for macOS..."
	@swift build

# Build for iOS
build-ios:
	@echo "Building for iOS..."
	@xcodebuild build -scheme UsefulThings -destination 'generic/platform=iOS' | grep -E "(Build succeeded|error:|note:)" || true

# Run tests (macOS only, as tests typically run on macOS)
test:
	@echo "Running tests..."
	@swift test

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@swift package clean
	@rm -rf .swiftpm/xcode
	@rm -rf .build
	@echo "✓ Clean complete"

# Show help
help:
	@echo "Available targets:"
	@echo "  make all        - Build for both macOS and iOS (default)"
	@echo "  make build      - Build for both macOS and iOS"
	@echo "  make build-macos - Build for macOS only"
	@echo "  make build-ios  - Build for iOS only"
	@echo "  make test       - Run tests"
	@echo "  make clean      - Clean build artifacts"
	@echo "  make help       - Show this help message"
