#
# Copyright (C) 2019-2021 Tiou
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=v2ray27
PKG_VERSION:=4.27.5
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/v2ray-core-$(PKG_VERSION)

PKG_SOURCE:=v2ray-core-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/v2fly/v2ray-core/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=f289d8d85ab0851851a6e3c101226e77bed0052fd60f9185df8852b601e657f8

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Tiou <dourokinga@gmail.com>

PKG_CONFIG_DEPENDS:= \
	CONFIG_V2RAY_COMPRESS_GOPROXY \
	CONFIG_V2RAY_COMPRESS_UPX

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0

GO_PKG:=v2ray.com/core
GO_PKG_LDFLAGS:=-s -w
GO_PKG_LDFLAGS_X:= \
	$(GO_PKG).version=$(PKG_VERSION) \
	$(GO_PKG).codename=OpenWrt

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/$(PKG_NAME)
  TITLE:=A platform for building proxies
  URL:=https://www.v2fly.org
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Project V
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-certificates
endef

define Package/$(PKG_NAME)/config
menu "V2Ray Configuration"
	depends on PACKAGE_v2ray

config V2RAY_COMPRESS_GOPROXY
	bool "Compiling with GOPROXY proxy"
	default n

config V2RAY_COMPRESS_UPX
	bool "Compress executable files with UPX"
	default y
endmenu
endef

define Package/$(PKG_NAME)/description
Project V is a set of network tools that help you to build your own computer network.
It secures your network connections and thus protects your privacy.

  This package contains v2ray, v2ctl, geoip.dat and geosite.dat.
endef

ifeq ($(CONFIG_V2RAY_COMPRESS_GOPROXY),y)
export GO111MODULE=on
export GOPROXY=https://goproxy.io
#export GOPROXY=https://mirrors.aliyun.com/goproxy/
endif

define Build/Prepare
	$(call Build/Prepare/Default)
endef

define Build/Compile
	$(eval GO_PKG_BUILD_PKG:=$(GO_PKG)/main)
	$(call GoPackage/Build/Compile)
	mv -f $(GO_PKG_BUILD_BIN_DIR)/main $(GO_PKG_BUILD_BIN_DIR)/v2ray27
ifeq ($(CONFIG_V2RAY_COMPRESS_UPX),y)
	$(STAGING_DIR_HOST)/bin/upx --lzma --best $(GO_PKG_BUILD_BIN_DIR)/v2ray27 || true
endif
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/v2ray27 $(1)/usr/bin
endef

$(eval $(call GoBinPackage,$(PKG_NAME)))
$(eval $(call BuildPackage,$(PKG_NAME)))
