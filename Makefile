# VibeUsage — macOS menu bar app
# 一站式构建 / 测试 / 打包 / 安装

APP_NAME       := VibeUsage
BUNDLE_ID      := com.vibe.vibeusage
VERSION        := 0.1.0

BUILD_DIR      := .build
DIST_DIR       := dist
APP_BUNDLE     := $(DIST_DIR)/$(APP_NAME).app
DMG_FILE       := $(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg
INFO_PLIST     := Resources/Info.plist

RELEASE_BIN    := $(BUILD_DIR)/release/$(APP_NAME)
DEBUG_BIN      := $(BUILD_DIR)/debug/$(APP_NAME)

# 代码签名身份；不签名留空 (Makefile 会回退到 ad-hoc 签名 "-")
CODESIGN_ID    ?= -

.DEFAULT_GOAL  := help

# ── 帮助 ───────────────────────────────────────────────────────────
.PHONY: help
help:
	@echo "VibeUsage — Makefile targets"
	@echo ""
	@echo "  make build      调试构建 (swift build)"
	@echo "  make release    发布构建 (-c release)"
	@echo "  make run        构建并运行调试版"
	@echo "  make test       运行 swift 测试"
	@echo "  make app        打包为 $(APP_NAME).app -> $(APP_BUNDLE)"
	@echo "  make icon       生成 AppIcon.icns -> $(ICON_FILE)"
	@echo "  make backend-build 构建 Go 后端二进制 -> $(BACKEND_BIN)"
	@echo "  make backend-test  运行 Go 后端测试"
	@echo "  make backend-vet   运行 go vet"
	@echo "  make backend-run   构建并运行后端 (数据目录 .tmp)"
	@echo "  make dev           调试模式并行启动前后端 (数据目录 $(DEV_DATA_DIR))"
	@echo "  make dmg        生成安装包 -> $(DMG_FILE)"
	@echo "  make install    安装到 /Applications"
	@echo "  make uninstall  从 /Applications 卸载"
	@echo "  make clean      清理 swift 构建产物"
	@echo "  make distclean  清理所有产物 (含 dist/)"
	@echo ""
	@echo "  CODESIGN_ID=\"Developer ID Application: 你的名字 (TEAMID)\" 可指定签名身份"

# ── 构建 ───────────────────────────────────────────────────────────
.PHONY: build
build:
	swift build

.PHONY: release
release:
	swift build -c release

.PHONY: run
run: build
	$(DEBUG_BIN)

# ── 测试 ───────────────────────────────────────────────────────────
.PHONY: test
test:
	swift test

# ── 应用图标 ───────────────────────────────────────────────────────
ICON_SRC      := tools/make_icon.swift
ICON_PNG      := .tmp/icon_1024.png
ICONSET_DIR   := .tmp/AppIcon.iconset
ICON_FILE     := Resources/AppIcon.icns

.PHONY: icon
icon: $(ICON_FILE)

$(ICON_FILE): $(ICON_SRC)
	@echo "→ 生成 AppIcon.icns"
	@rm -rf $(ICONSET_DIR)
	@mkdir -p $(ICONSET_DIR)
	@swift $(ICON_SRC) $(ICON_PNG) > /dev/null
	@sips -z   16   16 $(ICON_PNG) --out $(ICONSET_DIR)/icon_16x16.png       > /dev/null
	@sips -z   32   32 $(ICON_PNG) --out $(ICONSET_DIR)/icon_16x16@2x.png    > /dev/null
	@sips -z   32   32 $(ICON_PNG) --out $(ICONSET_DIR)/icon_32x32.png       > /dev/null
	@sips -z   64   64 $(ICON_PNG) --out $(ICONSET_DIR)/icon_32x32@2x.png    > /dev/null
	@sips -z  128  128 $(ICON_PNG) --out $(ICONSET_DIR)/icon_128x128.png     > /dev/null
	@sips -z  256  256 $(ICON_PNG) --out $(ICONSET_DIR)/icon_128x128@2x.png  > /dev/null
	@sips -z  256  256 $(ICON_PNG) --out $(ICONSET_DIR)/icon_256x256.png     > /dev/null
	@sips -z  512  512 $(ICON_PNG) --out $(ICONSET_DIR)/icon_256x256@2x.png  > /dev/null
	@sips -z  512  512 $(ICON_PNG) --out $(ICONSET_DIR)/icon_512x512.png     > /dev/null
	@cp $(ICON_PNG) $(ICONSET_DIR)/icon_512x512@2x.png
	@iconutil -c icns -o $(ICON_FILE) $(ICONSET_DIR)
	@echo "✓ $(ICON_FILE)"

# ── 打包成 .app ───────────────────────────────────────────────────
.PHONY: app
app: release backend-build icon
	@echo "→ 组装 $(APP_BUNDLE)"
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(RELEASE_BIN) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp $(BACKEND_BIN) $(APP_BUNDLE)/Contents/Resources/vibeusage-backend
	@cp $(ICON_FILE)   $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp $(INFO_PLIST)  $(APP_BUNDLE)/Contents/Info.plist
	@echo "→ 代码签名 (CODESIGN_ID=$(CODESIGN_ID))"
	@codesign --force --options runtime --sign "$(CODESIGN_ID)" $(APP_BUNDLE)/Contents/Resources/vibeusage-backend
	@codesign --force --options runtime --sign "$(CODESIGN_ID)" $(APP_BUNDLE)
	@echo "✓ $(APP_BUNDLE)"

# ── 生成 DMG 安装包 (含 Applications 软链) ──────────────────────────
DMG_STAGE := .tmp/dmg-stage

.PHONY: dmg
dmg: app
	@echo "→ 准备 DMG 内容 (含 Applications 软链)"
	@rm -rf $(DMG_STAGE)
	@mkdir -p $(DMG_STAGE)
	@cp -R $(APP_BUNDLE) $(DMG_STAGE)/
	@ln -s /Applications $(DMG_STAGE)/Applications
	@echo "→ 生成 $(DMG_FILE)"
	@rm -f $(DMG_FILE)
	@hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder $(DMG_STAGE) \
		-ov -format UDZO \
		$(DMG_FILE) >/dev/null
	@rm -rf $(DMG_STAGE)
	@echo "✓ $(DMG_FILE) ($(shell du -h $(DMG_FILE) 2>/dev/null | cut -f1))"

# ── 安装 / 卸载 ───────────────────────────────────────────────────
.PHONY: install
install: app
	@echo "→ 安装到 /Applications/$(APP_NAME).app"
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) "/Applications/$(APP_NAME).app"
	@echo "✓ 安装完成，可在启动台搜索 $(APP_NAME) 启动"

.PHONY: uninstall
uninstall:
	@rm -rf "/Applications/$(APP_NAME).app"
	@echo "✓ 已卸载"

# ── Go backend ────────────────────────────────────────────────────
BACKEND_BIN := $(DIST_DIR)/vibeusage-backend

.PHONY: backend-build
backend-build:
	@echo "→ go build vibeusage-backend"
	@mkdir -p $(DIST_DIR)
	@cd backend && CGO_ENABLED=0 go build -trimpath \
		-ldflags "-s -w -X main.version=$(VERSION)" \
		-o ../$(BACKEND_BIN) \
		./cmd/vibeusage-backend
	@echo "✓ $(BACKEND_BIN) ($$(du -h $(BACKEND_BIN) | cut -f1))"

.PHONY: backend-test
backend-test:
	@cd backend && go test ./... -race -count=1

.PHONY: backend-vet
backend-vet:
	@cd backend && go vet ./...

.PHONY: backend-run
backend-run: backend-build
	@mkdir -p .tmp
	@$(BACKEND_BIN) --data-dir .tmp --log-level debug

# ── 调试模式 (前后端一起跑) ───────────────────────────────────────
DEV_DATA_DIR := .tmp/dev
DEV_BACKEND  := .tmp/bin/vibeusage-backend-dev

.PHONY: dev
dev:
	@mkdir -p $(DEV_DATA_DIR) .tmp/bin
	@echo "→ 构建后端 (debug)"
	@cd backend && go build -o ../$(DEV_BACKEND) ./cmd/vibeusage-backend
	@echo "→ 启动后端 + 前端 (Ctrl+C 退出)"
	@bash -c 'set -e; \
		./$(DEV_BACKEND) --data-dir $(DEV_DATA_DIR) --log-level debug --tick 10s & \
		BACKEND_PID=$$!; \
		trap "echo; echo \"→ 停止后端 (pid=$$BACKEND_PID)\"; kill $$BACKEND_PID 2>/dev/null; wait 2>/dev/null; exit 0" INT TERM; \
		VIBEUSAGE_DATA_DIR="$$PWD/$(DEV_DATA_DIR)" swift run VibeUsage 2> >(grep -v "IMKCFRunLoopWakeUpReliable" >&2); \
		kill $$BACKEND_PID 2>/dev/null || true'

# ── 清理 ──────────────────────────────────────────────────────────
.PHONY: clean
clean:
	swift package clean
	rm -rf $(BUILD_DIR)

.PHONY: distclean
distclean: clean
	rm -rf $(DIST_DIR)
