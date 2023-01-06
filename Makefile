VERSION ?= 0.0.0

.PHONY: all
all: debug

.PHONY: debug
debug: deps/dist set-version
	xcodebuild -workspace ShadowsocksX-NG.xcworkspace -scheme ShadowsocksX-NG -configuration Debug SYMROOT=$${PWD}/build

.PHONY: release
release: deps/dist set-version
	xcodebuild -workspace ShadowsocksX-NG.xcworkspace -scheme ShadowsocksX-NG -configuration Release SYMROOT=$${PWD}/build

.PHONY: debug-dmg release-dmg
debug-dmg release-dmg: TARGET = $(subst -dmg,,$@)
debug-dmg release-dmg:
	t="$(TARGET)" && t="`tr '[:lower:]' '[:upper:]' <<< $${t:0:1}`$${t:1}" \
	  && rm -rf build/$${t}/ShadowsocksX-NG/ \
	  && mkdir build/$${t}/ShadowsocksX-NG \
	  && cp -r build/$${t}/ShadowsocksX-NG.app build/$${t}/ShadowsocksX-NG/ \
	  && ln -s /Applications build/$${t}/ShadowsocksX-NG/Applications \
	  && hdiutil create build/$${t}/ShadowsocksX-NG.dmg -ov -volname "ShadowsocksX-NG" -fs HFS+ -srcfolder build/$${t}/ShadowsocksX-NG/ \
          && rm -rf build/$${t}/ShadowsocksX-NG/

.PHONY: set-version
set-version:
	agvtool new-marketing-version $(VERSION)

deps/dist:
	$(MAKE) -C deps

.PHONY: clean
clean:
	$(MAKE) -C deps clean
