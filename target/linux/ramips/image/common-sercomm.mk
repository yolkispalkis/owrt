DEVICE_VARS += SERCOMM_KERNEL_OFFSET SERCOMM_ROOTFS_OFFSET

define Build/sercomm-crypto
	$(TOPDIR)/scripts/sercomm-crypto.py \
		--input-file $@ \
		--key-file $@.key \
		--output-file $@.ser \
		--version $(SERCOMM_SWVER)
	$(STAGING_DIR_HOST)/bin/openssl enc -md md5 -aes-256-cbc \
		-in $@ \
		-out $@.enc \
		-K `cat $@.key` \
		-iv 00000000000000000000000000000000
	dd if=$@.enc >> $@.ser 2>/dev/null
	mv $@.ser $@
	rm -f $@.enc $@.key
endef

define Build/sercomm-kernel
	$(TOPDIR)/scripts/sercomm-kernel-header.py \
		--kernel-image $@ \
		--kernel-offset $(SERCOMM_KERNEL_OFFSET) \
		--rootfs-offset $(SERCOMM_ROOTFS_OFFSET) \
		--output-header $@.hdr
	dd if=$@ >> $@.hdr 2>/dev/null
	mv $@.hdr $@
endef

define Build/sercomm-part-tag
	$(call Build/sercomm-part-tag-common,$(word 1,$(1)) $@)
endef

define Build/sercomm-part-tag-common
	$(eval file=$(word 2,$(1)))
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $(file) \
		--output-file $(file).tmp \
		--part-name $(word 1,$(1)) \
		--part-version $(SERCOMM_SWVER)
	mv $(file).tmp $(file)
endef

define Build/sercomm-payload
	$(TOPDIR)/scripts/sercomm-pid.py \
		--hw-version $(SERCOMM_HWVER) \
		--hw-id $(SERCOMM_HWID) \
		--sw-version $(SERCOMM_SWVER) \
		--pid-file $@.pid \
		--extra-padding-size 0x10 \
		--extra-padding-first-byte 0x0a
	$(TOPDIR)/scripts/sercomm-payload.py \
		--input-file $@ \
		--output-file $@.tmp \
		--pid "$$(cat $@.pid | od -t x1 -An -v | tr -d '\n')"
	mv $@.tmp $@
	rm $@.pid
endef

define Build/sercomm-prepend-tagged-kernel
	$(CP) $(IMAGE_KERNEL) $(IMAGE_KERNEL).tagged
	$(call Build/sercomm-part-tag-common,$(word 1,$(1)) \
		$(IMAGE_KERNEL).tagged)
	dd if=$@ >> $(IMAGE_KERNEL).tagged 2>/dev/null
	mv $(IMAGE_KERNEL).tagged $@
endef

define Device/sercomm_dxx
  $(Device/dsa-migration)
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_SIZE := 6144k
  UBINIZE_OPTS := -E 5
  LOADER_TYPE := bin
  KERNEL_LOADADDR := 0x81001000
  LZMA_TEXT_START := 0x82800000
  KERNEL := kernel-bin | append-dtb | lzma | loader-kernel | lzma -a0 | \
	uImage lzma | sercomm-kernel
  KERNEL_INITRAMFS := kernel-bin | append-dtb | lzma | loader-kernel | \
	lzma -a0 | uImage lzma
  IMAGES += factory.img
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  IMAGE/factory.img := append-ubi | sercomm-part-tag rootfs | \
	sercomm-prepend-tagged-kernel kernel | gzip | sercomm-payload | \
	sercomm-crypto
  SERCOMM_KERNEL_OFFSET := 0x400100
  SERCOMM_ROOTFS_OFFSET := 0x1000000
endef

define Build/sercomm-part-tag-common2
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $(word 2,$(1)) \
		--output-file $(word 3,$(1)) \
		--part-name $(word 1,$(1)) \
		--part-version $(SERCOMM_SWVER)
endef

define Build/sercomm-factory-s1010_cpj_16m
	# Этот скрипт должен общий образ firmware
	#	разделить на kernel 2 МиБ и остальное rootfs
	dd if=$@ count=$((0x200000)) iflag=count_bytes of=$@.kernel 2>/dev/null
	dd if=$@ skip=$((0x200000)) iflag=skip_bytes of=$@.rootfs 2>/dev/null
	$(call Build/sercomm-part-tag-common2,kernel $@.kernel $@.kerneltag)
	$(call Build/sercomm-part-tag-common2,rootfs $@.rootfs $@.rootfstag)
	cat $@.kernel $@.kerneltag $@.rootfs $@.rootfstag >> $@.tagged 2>/dev/null
	mv $@.tagged $@
endef

define Device/sercomm_s1010
	$(Device/dsa-migration)
	LOADER_TYPE := bin
	KERNEL := kernel-bin | append-dtb | lzma | loader-kernel | lzma -a0 | \
		uImage lzma | sercomm-kernel
	KERNEL_INITRAMFS := kernel-bin | append-dtb | lzma | loader-kernel | \
		lzma -a0 | uImage lzma
	IMAGES += factory.img
	IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
	IMAGE/factory.img := $$(sysupgrade_bin) | check-size | \
		sercomm-factory-s1010_cpj_16m | gzip | sercomm-payload | \
		sercomm-crypto
	SERCOMM_KERNEL_OFFSET := 0x70000
	SERCOMM_ROOTFS_OFFSET := 0x270000
endef
