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
PKG_SOURCE_DATE:=2022-05-30
PKG_SOURCE_VERSION:=59053ba00e61731e7385ac8ce24ecf36948d7008
# PKG_MIRROR_HASH:=6ab19b53f8123de5408fa1cda711143b2fb80a6b862b8e8294832c2b9df7b017

include $(INCLUDE_DIR)/host-build.mk
include $(INCLUDE_DIR)/cmake.mk

$(eval $(call HostBuild))
