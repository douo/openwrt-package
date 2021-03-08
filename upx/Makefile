#
# Copyright (C) 2011-2020 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=upx
PKG_VERSION:=3.95

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION)-src.tar.xz
PKG_SOURCE_URL:=https://github.com/upx/upx/releases/download/v$(PKG_VERSION)
PKG_HASH:=3b0f55468d285c760fcf5ea865a070b27696393002712054c69ff40d8f7f5592

HOST_BUILD_DIR:=$(BUILD_DIR_HOST)/$(PKG_NAME)-$(PKG_VERSION)-src
PKG_HOST_ONLY:=1
HOST_BUILD_DEPENDS:=ucl/host

include $(INCLUDE_DIR)/host-build.mk
include $(INCLUDE_DIR)/package.mk

define Package/upx
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=The Ultimate Packer for eXecutables
  URL:=https://upx.github.io/
  BUILDONLY:=1
endef
define Package/node-yarn/description
 The Ultimate Packer for eXecutables
endef


define Host/Compile
	UPX_UCLDIR=$(HOST_BUILD_PREFIX) \
	$(MAKE) -C $(HOST_BUILD_DIR)/src \
		CXXFLAGS_WERROR="" LDFLAGS="$(HOST_LDFLAGS)" \
		CXX="$(HOSTCXX)"
endef

define Host/Install
	$(CP) $(HOST_BUILD_DIR)/src/upx.out $(STAGING_DIR_HOST)/bin/upx
endef

define Host/Clean
	rm -f $(STAGING_DIR_HOST)/bin/upx
endef

$(eval $(call HostBuild))
$(eval $(call BuildPackage,upx))
