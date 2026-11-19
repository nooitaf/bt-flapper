APP_NAME := bt-flapper
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
BINARY := .build/release/$(APP_NAME)
INSTALL_DIR := /Applications

.PHONY: all build icon app install uninstall run test clean

all: app

build:
	swift build -c release

icon:
	@swift Scripts/generate_icon.swift Resources/AppIcon.png
	@rm -rf build/AppIcon.iconset
	@mkdir -p build/AppIcon.iconset
	@sips -z 16 16     Resources/AppIcon.png --out build/AppIcon.iconset/icon_16x16.png >/dev/null
	@sips -z 32 32     Resources/AppIcon.png --out build/AppIcon.iconset/icon_16x16@2x.png >/dev/null
	@sips -z 32 32     Resources/AppIcon.png --out build/AppIcon.iconset/icon_32x32.png >/dev/null
	@sips -z 64 64     Resources/AppIcon.png --out build/AppIcon.iconset/icon_32x32@2x.png >/dev/null
	@sips -z 128 128   Resources/AppIcon.png --out build/AppIcon.iconset/icon_128x128.png >/dev/null
	@sips -z 256 256   Resources/AppIcon.png --out build/AppIcon.iconset/icon_128x128@2x.png >/dev/null
	@sips -z 256 256   Resources/AppIcon.png --out build/AppIcon.iconset/icon_256x256.png >/dev/null
	@sips -z 512 512   Resources/AppIcon.png --out build/AppIcon.iconset/icon_256x256@2x.png >/dev/null
	@sips -z 512 512   Resources/AppIcon.png --out build/AppIcon.iconset/icon_512x512.png >/dev/null
	@cp Resources/AppIcon.png build/AppIcon.iconset/icon_512x512@2x.png
	@iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	@rm -rf build/AppIcon.iconset
	@echo "Generated Resources/AppIcon.icns"

app: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

install: app
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Removed $(INSTALL_DIR)/$(APP_NAME).app"

run: app
	@open "$(APP_BUNDLE)"

test:
	swift run BTFlapperTests

clean:
	swift package clean
	rm -rf "$(BUILD_DIR)"
