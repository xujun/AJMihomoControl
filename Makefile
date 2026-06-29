APP_NAME = MihomoControl
APP_VERSION = 1.1.1
APP_BUNDLE = $(APP_NAME).app
RELEASE_DIR = release
DMG_NAME = $(APP_NAME)-v$(APP_VERSION).dmg

.PHONY: all build clean install run release

all: build

# 构建 .app bundle
build:
	@echo "==> 正在构建 $(APP_NAME)..."
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@cp AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@echo "  编译 x86_64..."
	@swiftc -O -target x86_64-apple-macosx14.0 -o x86_64_bin Sources/*.swift -framework Cocoa -framework SwiftUI
	@echo "  编译 arm64..."
	@swiftc -O -target arm64-apple-macosx14.0 -o arm64_bin Sources/*.swift -framework Cocoa -framework SwiftUI
	@echo "  合并 Universal Binary..."
	@lipo -create -output "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" x86_64_bin arm64_bin
	@rm -f x86_64_bin arm64_bin
	@chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@codesign --force --deep --sign - "$(APP_BUNDLE)" 2>/dev/null || true
	@echo "==> 完成：$(APP_BUNDLE)"

# 构建发布版本
release: build
	@echo "==> 正在打包发布文件..."
	@rm -rf "$(RELEASE_DIR)"
	@mkdir -p "$(RELEASE_DIR)"
	@cp -R "$(APP_BUNDLE)" "$(RELEASE_DIR)/"
	@cp README.md "$(RELEASE_DIR)/"
	@echo "==> 发布包已创建：$(RELEASE_DIR)/$(APP_NAME)/"

# 创建 DMG 安装镜像（拖拽安装）
dmg: release
	@echo "==> 正在创建 DMG 安装镜像..."
	@rm -f $(DMG_NAME)
	@rm -rf /tmp/MihomoControl-dmg
	@mkdir -p /tmp/MihomoControl-dmg
	@cp -R MihomoControl.app /tmp/MihomoControl-dmg/
	@ln -s /Applications /tmp/MihomoControl-dmg/Applications
	@hdiutil create -volname "MihomoControl Installer" -srcfolder /tmp/MihomoControl-dmg -ov -format UDZO $(DMG_NAME)
	@rm -rf /tmp/MihomoControl-dmg
	@ls -lh $(DMG_NAME)
	@echo "==> DMG 安装镜像已创建：$(DMG_NAME)"

clean:
	rm -rf "$(APP_BUNDLE)" "$(RELEASE_DIR)"

install: build
	@echo "==> 安装到 /Applications..."
	@cp -R "$(APP_BUNDLE)" /Applications/
	@echo "==> 已安装：/Applications/$(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

# 安装 mihomo
install-mihomo:
	@echo "==> 安装 mihomo..."
	brew install mihomo
	@mkdir -p /usr/local/etc/mihomo
	@if [ ! -f /usr/local/etc/mihomo/config.yaml ]; then \
		echo "# mihomo config" > /usr/local/etc/mihomo/config.yaml; \
		echo "已创建配置文件"; \
	fi
