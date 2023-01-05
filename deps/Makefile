override ARCH ?= $(shell uname -m)

ifeq ($(ARCH),arm64)
override ARCH := aarch64
endif

TARGET := $(ARCH)-apple-macos10.12
JOBS := $(shell getconf _NPROCESSORS_ONLN)
GOROOT := $${PWD}/../dist/go
GO := $(GOROOT)/bin/go

ifeq ($(ARCH),x86_64)
GOARCH := amd64
else
GOARCH := arm64
endif

.PHONY: all
all: 
	$(MAKE) ARCH=x86_64 shadowsocks-libev privoxy simple-obfs v2ray-plugin kcptun
	$(MAKE) ARCH=aarch64 shadowsocks-libev privoxy simple-obfs v2ray-plugin kcptun
	$(MAKE) universal

.PHONY: universal
universal:
	# shadowsocks-libev
	mkdir -p $${PWD}/dist/universal/shadowsocks-libev/bin
	lipo \
		$${PWD}/dist/x86_64/shadowsocks-libev/bin/ss-local \
		$${PWD}/dist/aarch64/shadowsocks-libev/bin/ss-local \
		-create \
		-output $${PWD}/dist/universal/shadowsocks-libev/bin/ss-local
	cp $${PWD}/dist/universal/shadowsocks-libev/bin/ss-local $${PWD}/../ShadowsocksX-NG/ss-local/

	# privoxy
	mkdir -p $${PWD}/dist/universal/privoxy/sbin
	lipo \
		$${PWD}/dist/x86_64/privoxy/sbin/privoxy \
		$${PWD}/dist/aarch64/privoxy/sbin/privoxy \
		-create \
		-output $${PWD}/dist/universal/privoxy/sbin/privoxy
	cp $${PWD}/dist/universal/privoxy/sbin/privoxy $${PWD}/../ShadowsocksX-NG/privoxy/

	# simple-obfs
	mkdir -p $${PWD}/dist/universal/simple-obfs/bin
	lipo \
		$${PWD}/dist/x86_64/simple-obfs/bin/obfs-local \
		$${PWD}/dist/aarch64/simple-obfs/bin/obfs-local \
		-create \
		-output $${PWD}/dist/universal/simple-obfs/bin/obfs-local
	cp $${PWD}/dist/universal/simple-obfs/bin/obfs-local $${PWD}/../ShadowsocksX-NG/simple-obfs/

	# v2ray-plugin
	mkdir -p $${PWD}/dist/universal/v2ray-plugin/bin
	lipo \
		$${PWD}/dist/x86_64/v2ray-plugin/bin/v2ray-plugin \
		$${PWD}/dist/aarch64/v2ray-plugin/bin/v2ray-plugin \
		-create \
		-output $${PWD}/dist/universal/v2ray-plugin/bin/v2ray-plugin
	cp $${PWD}/dist/universal/v2ray-plugin/bin/v2ray-plugin $${PWD}/../ShadowsocksX-NG/v2ray-plugin/

	# kcptun
	mkdir -p $${PWD}/dist/universal/kcptun/bin
	lipo \
		$${PWD}/dist/x86_64/kcptun/bin/client \
		$${PWD}/dist/aarch64/kcptun/bin/client \
		-create \
		-output $${PWD}/dist/universal/kcptun/bin/client
	cp $${PWD}/dist/universal/kcptun/bin/client $${PWD}/../ShadowsocksX-NG/kcptun/

.PHONY: pcre
pcre:
	[ -f pcre.tar.gz ] || curl -L -o pcre.tar.gz 'https://downloads.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.gz'
	tar -xf pcre.tar.gz
	cd pcre-8.45 \
		&& CXXFLAGS="-target $(TARGET)" CFLAGS="-target $(TARGET)" ./configure --prefix $${PWD}/../dist/$(ARCH)/pcre \
		--host=$(TARGET) \
		--disable-dependency-tracking \
		--enable-utf8 \
		--enable-pcre8 \
		--enable-pcre16 \
		--enable-pcre32 \
		--enable-unicode-properties \
		--enable-pcregrep-libz \
		--enable-pcregrep-libbz2 \
		--enable-static \
		--disable-shared \
		&& make -j$(JOBS) \
		&& make install \
		&& make clean

.PHONY: libev
libev:
	[ -f libev.tar.gz ] || curl -L -o libev.tar.gz 'http://dist.schmorp.de/libev/libev-4.33.tar.gz'
	tar -xf libev.tar.gz
	cd libev-4.33 \
		&& CFLAGS="-target $(TARGET)" ./configure --prefix $${PWD}/../dist/$(ARCH)/libev \
		--host=$(TARGET) \
		--disable-dependency-tracking \
		--enable-static \
		--disable-shared \
		&& make -j$(JOBS) \
		&& make install \
		&& make clean

.PHONY: privoxy
privoxy:
	[ -f privoxy.tar.gz ] || curl -L -o privoxy.tar.gz 'https://www.privoxy.org/sf-download-mirror/Sources/3.0.33%20%28stable%29/privoxy-3.0.33-stable-src.tar.gz'
	tar -xf privoxy.tar.gz
	cd privoxy-3.0.33-stable \
		&& patch -Ru configure.in < $${PWD}/../patch/privoxy/configure.in.patch \
		&& autoreconf -fi \
		&& LDFLAGS="-target $(TARGET) -L$${PWD}/../dist/$(ARCH)/pcre/lib" \
		CPPFLAGS="-target $(TARGET) -Dunix -I$${PWD}/../dist/$(ARCH)/pcre/include" \
		CFLAGS="-target $(TARGET) -Dunix -I$${PWD}/../dist/$(ARCH)/pcre/include" \
		./configure --prefix $${PWD}/../dist/$(ARCH)/privoxy \
		--host=$(TARGET) \
		--disable-debug \
		&& make -j$(JOBS) \
		&& make install \
		&& make clean

.PHONY: c-ares
c-ares:
	cd c-ares \
		&& autoreconf -fi \
		&& CXXFLAGS="-target $(TARGET)" CFLAGS="-target $(TARGET)" ./configure --prefix=$${PWD}/../dist/$(ARCH)/c-ares \
		--host=$(TARGET) \
		--disable-dependency-tracking \
		--enable-static \
		--disable-shared \
		&& make -j$(JOBS) \
		&& make install \
		&& make clean

.PHONY: libsodium
libsodium:
	cd libsodium \
		&& ./autogen.sh \
		&& CFLAGS="-target $(TARGET)" ./configure --prefix $${PWD}/../dist/$(ARCH)/libsodium \
		--host=$(TARGET) \
		--enable-static \
		--disable-shared \
		&& make -j$(JOBS) \
		&& make install \
		&& make clean

.PHONY: mbedtls
mbedtls:
	cd mbedtls \
		&& make CFLAGS="-target $(TARGET) -O2" LDFLAGS="-target $(TARGET) -O2" -j$(JOBS)\
		&& make DESTDIR=$${PWD}/../dist/$(ARCH)/mbedtls install \
		&& make clean

.PHONY: shadowsocks-libev
shadowsocks-libev: pcre libev c-ares libsodium mbedtls 
	cd shadowsocks-libev \
		&& ./autogen.sh \
		&& CFLAGS="-target $(TARGET)" LDFLAGS="-lresolv" ./configure --prefix $${PWD}/../dist/$(ARCH)/shadowsocks-libev \
		--host=$(TARGET) \
		--disable-dependency-tracking \
		--enable-static \
		--disable-shared \
		--disable-documentation \
		--with-mbedtls=$${PWD}/../dist/$(ARCH)/mbedtls \
		--with-pcre=$${PWD}/../dist/$(ARCH)/pcre \
		--with-sodium=$${PWD}/../dist/$(ARCH)/libsodium \
		--with-cares=$${PWD}/../dist/$(ARCH)/c-ares \
		--with-ev=$${PWD}/../dist/$(ARCH)/libev \
		&& make -j$(JOBS) \
		&& make install \
		&& make clean

.PHONY: simple-obfs
simple-obfs:
	cd simple-obfs \
		&& ./autogen.sh \
		&& CFLAGS="-target $(TARGET)" ./configure --prefix=$${PWD}/../dist/$(ARCH)/simple-obfs \
		--host=$(TARGET) \
		--disable-dependency-tracking \
		--disable-documentation \
		--enable-static \
		--disable-shared \
		--with-ev=$${PWD}/../dist/$(ARCH)/libev \
		&& make -j$(JOBS) \
		&& make install \
		&& make clean

.PHONY: v2ray-plugin
v2ray-plugin: go
	cd v2ray-plugin \
		&& GOROOT=$(GOROOT) GOOS=darwin GOARCH=$(GOARCH) \
			$(GO) build -trimpath -ldflags "-s -w" -o $${PWD}/../dist/$(ARCH)/v2ray-plugin/bin/v2ray-plugin 

.PHONY: kcptun
kcptun: go
	cd kcptun \
		&& GOROOT=$(GOROOT) GOOS=darwin GOARCH=$(GOARCH) \
			$(GO) build -trimpath -ldflags "-s -w" -o $${PWD}/../dist/$(ARCH)/kcptun/bin/client github.com/xtaci/kcptun/client 

.PHONY: go
go:
	[ -d dist ] || mkdir dist
ifeq ($(shell uname -m),arm64)
	[ -f dist/go.tar.gz ] || curl "https://dl.google.com/go/go1.18.darwin-arm64.tar.gz" --output dist/go.tar.gz
else
	[ -f dist/go.tar.gz ] || curl "https://dl.google.com/go/go1.18.darwin-amd64.tar.gz" --output dist/go.tar.gz
endif
	cd dist \
		&& tar -zxf go.tar.gz

clean:
	rm -rf dist
	rm -rf pcre*
	rm -rf libev*
	rm -rf privoxy*
