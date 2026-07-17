PLUGIN_DIR := lr-plugin/BulkJpegSync.lrdevplugin
DIST_DIR := dist
ARCHIVE := $(DIST_DIR)/BulkJpegSync.lrplugin.zip
TEMP_ARCHIVE := $(DIST_DIR)/BulkJpegSync.lrplugin.tmp.zip
LUA_FILES := $(shell find $(PLUGIN_DIR) tests -name '*.lua' 2>/dev/null)

.PHONY: lint test build verify-package check clean

lint:
	@for file in $(LUA_FILES); do luac -p "$$file"; done

test:
	lua tests/run.lua

build:
	mkdir -p $(DIST_DIR)
	rm -f $(TEMP_ARCHIVE)
	cd lr-plugin && zip -qr ../$(TEMP_ARCHIVE) BulkJpegSync.lrdevplugin
	mv $(TEMP_ARCHIVE) $(ARCHIVE)

verify-package: build
	@source_list=$$(mktemp); archive_list=$$(mktemp); \
	trap 'rm -f "$$source_list" "$$archive_list"' EXIT; \
	cd lr-plugin && find BulkJpegSync.lrdevplugin -type f | sort > "$$source_list"; \
	cd .. && unzip -Z1 $(ARCHIVE) | sed '/\/$$/d' | sort > "$$archive_list"; \
	diff -u "$$source_list" "$$archive_list"

check: lint test verify-package

clean:
	rm -rf $(DIST_DIR)
