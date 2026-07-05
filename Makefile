PLUGIN_DIR := lr-plugin/BulkJpegSync.lrdevplugin
DIST_DIR := dist
LUA_FILES := $(shell find $(PLUGIN_DIR) tests -name '*.lua' 2>/dev/null)

.PHONY: lint test build clean

lint:
	@for file in $(LUA_FILES); do luac -p "$$file"; done

test:
	lua tests/run.lua

build:
	mkdir -p $(DIST_DIR)
	cd lr-plugin && zip -qr ../$(DIST_DIR)/BulkJpegSync.lrplugin.zip BulkJpegSync.lrdevplugin

clean:
	rm -rf $(DIST_DIR)
