APP_NAME = MihomoControl
APP_BUNDLE = $(APP_NAME).app
RELEASE_DIR = release

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
	@swiftc -O -o "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" \
		Sources/*.swift \
		-framework Cocoa -framework SwiftUI
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
	@rm -f "$(APP_NAME)-v1.0.0.dmg"
	@rm -f "$(APP_NAME)-tmp.dmg"
	@rm -rf /tmp/$(APP_NAME)-dmg
	@mkdir -p /tmp/$(APP_NAME)-dmg
	@cp -R "$(APP_BUNDLE)" /tmp/$(APP_NAME)-dmg/
	@ln -s /Applications /tmp/$(APP_NAME)-dmg/Applications
	@hdiutil create -srcfolder /tmp/$(APP_NAME)-dmg -volname "$(APP_NAME) Installer" \
		-fs HFS+ -format UDRW -size 50m "$(APP_NAME)-tmp.dmg" 2>/dev/null
	@MOUNT=$$(hdiutil attach -nobrowse "$(APP_NAME)-tmp.dmg" 2>/dev/null | grep "Apple_HFS" | awk '{print $$NF}'); \
	echo "  挂载于 $$MOUNT"; \
	sleep 2; \
	osascript -e ' \
		tell application "Finder" \
			delay 1 \
			set volName to "$(APP_NAME) Installer" \
			set dmgDisk to disk volName \
			open dmgDisk \
			delay 1 \
			set w to window of dmgDisk \
			set current view of w to icon view \
			set toolbar visible of w to false \
			set statusbar visible of w to false \
			set the bounds of w to {400, 100, 920, 440} \
			set theViewOptions to the icon view options of w \
			set arrangement of theViewOptions to not arranged \
			set icon size of theViewOptions to 100 \
			set position of item "$(APP_NAME).app" of w to {130, 160} \
			set position of item "Applications" of w to {380, 160} \
			delay 1 \
			close w \
		end tell \
	' 2>/dev/null; \
	sleep 1; \
	hdiutil detach "$$MOUNT" 2>/dev/null; \
	sleep 1; \
	hdiutil convert "$(APP_NAME)-tmp.dmg" -format UDZO -imagekey zlib-level=9 \
		-o "$(APP_NAME)-v1.0.0.dmg" 2>/dev/null; \
	rm -f "$(APP_NAME)-tmp.dmg"; \
	rm -rf /tmp/$(APP_NAME)-dmg; \
	ls -lh "$(APP_NAME)-v1.0.0.dmg" 2>/dev/null; \
	echo "==> DMG 安装镜像已创建：$(APP_NAME)-v1.0.0.dmg"

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
