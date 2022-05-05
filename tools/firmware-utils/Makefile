#
# Copyright (C) 2006-2020 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=firmware-utils
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL=https://gitlab.com/openwrt-dev-ru-smartbox/openwrt-firmware-utils.git
PKG_SOURCE_DATE:=2022-05-11
PKG_SOURCE_VERSION:=0ed483b20d70f484101af5b8a416801b6ad0b52c
# PKG_MIRROR_HASH:=246fc1d72d3a8cdb4072d81e033c92abaf614acd6f35a10fffd029d5c7f9303b

include $(INCLUDE_DIR)/host-build.mk
include $(INCLUDE_DIR)/cmake.mk

$(eval $(call HostBuild))
