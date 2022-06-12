DEVICE_VARS += SERCOMM_KERNEL0_OFFSET SERCOMM_ROOTFS0_OFFSET
DEVICE_VARS += SERCOMM_KERNEL1_OFFSET SERCOMM_ROOTFS1_OFFSET
DEVICE_VARS += SERCOMM_0x0str SERCOMM_0x04str SERCOMM_0x10str
DEVICE_VARS += SERCOMM_str0x4c SERCOMM_str0x5c

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

define Build/sercomm-part-tag
	$(eval tag=$(word 1,$(1)))
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $@ \
		--output-file $@.tmp \
		--part-name $(tag) \
		--part-version $(SERCOMM_SWVER)
	mv $@.tmp $@
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
	$(eval kernel_tag=$(word 1,$(1)))
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $(IMAGE_KERNEL) \
		--output-file $(IMAGE_KERNEL).tagged \
		--part-name $(kernel_tag) \
		--part-version $(SERCOMM_SWVER)
	dd if=$@ >> $(IMAGE_KERNEL).tagged
	mv $(IMAGE_KERNEL).tagged $@
endef

define Build/sercomm-s3-kernel
	$(TOPDIR)/scripts/sercomm-kernel-header.py \
		--kernel-image $@ \
		--kernel-offset $(SERCOMM_KERNEL0_OFFSET) \
		--rootfs-offset $(SERCOMM_ROOTFS0_OFFSET) \
		--output-header $@.hdr
	dd if=$@ >> $@.hdr 2>/dev/null
	mv $@.hdr $@
endef


define Build/sercomm-tag-header-kernel
  $(eval kernel_offset=$(word 1,$(1)))
  $(eval rootfs_offset=$(word 2,$(1)))
  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(kernel_offset) \
    -b $(rootfs_offset) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn
  cat $@.hdrkrn $(IMAGE_KERNEL) > $@.new
  mv $@.new $@ ; rm -f $@.hdrkrn
endef

define Build/sercomm-tag-factory-type-A-hack
  # 
  head -c 4 $@ > $@.rootfscut
  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL0_OFFSET) \
    -b $(SERCOMM_ROOTFS0_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@.rootfscut \
    -e $@.hdrkrn1
  cat $@.hdrkrn1 $(IMAGE_KERNEL) > $@.krn1
  # 
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $@.krn1 \
		--output-file $@.kernel \
		--part-name kernel \
		--part-version $(SERCOMM_SWVER)
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $@ \
		--output-file $@.rootfs \
		--part-name rootfs \
		--part-version $(SERCOMM_SWVER)

  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL1_OFFSET) \
    -b $(SERCOMM_ROOTFS1_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn2 \
    -f 
  cat $@.hdrkrn2 $(IMAGE_KERNEL) > $@.krn2

	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $@.krn1 \
		--output-file $@.kernel2 \
		--part-name kernel2 \
		--part-version $(SERCOMM_SWVER)
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $@ \
		--output-file $@.rootfs2 \
		--part-name rootfs2 \
		--part-version $(SERCOMM_SWVER)
  cat $@.kernel $@.rootfs $@.kernel2 $@.rootfs2 > $@.frst

  # 
	gzip -f -9n -c $@.frst > $@.gz

  # 
  $(STAGING_DIR_HOST)/bin/sercomm_tag_pid \
    -a $(SERCOMM_0x0str) \
    -b $(SERCOMM_0x04str) \
    -c $(SERCOMM_HWID) \
    -g $(SERCOMM_SWVER) \
    -o $@.pid
  dd if=/dev/zero bs=1 count=16 seek=$$((0x70)) of=$@.pid conv=notrunc
  printf '\x0a' | dd of=$@.pid bs=1 seek=$$((0x70)) conv=notrunc

	$(TOPDIR)/scripts/sercomm-payload.py \
		--input-file $@.gz \
		--output-file $@.scnd \
		--pid "$$(cat $@.pid | od -t x1 -An -v | tr -d '\n')"
	$(TOPDIR)/scripts/sercomm-crypto.py \
		--input-file $@.scnd \
		--key-file $@.key \
		--output-file $@.hdrenc \
		--version $(SERCOMM_SWVER)
	$(STAGING_DIR_HOST)/bin/openssl enc -md md5 -aes-256-cbc \
		-in $@.scnd -out $@.enc \
		-K `cat $@.key` \
		-iv 00000000000000000000000000000000
  cat $@.hdrenc $@.enc > $@.new
	mv $@.new $@
	rm -f $@.hdrkrn1 $@.krn1 $@.kernel $@.rootfs $@.hdrkrn2 $@.krn2 \
    $@.kernel2 $@.rootfs2 $@.frst $@.gz $@.pid $@.scnd \
    $@.key $@.hdrenc $@.enc $@.rootfscut
endef

define Build/fake-rootfs-CRC32
# Read first 4 byte for CRC32 verify
	head -n 4 $@ > $@.new
	@mv $@.new $@
endef

define Build/sercomm-tag-factory-type-A
  # 
  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL0_OFFSET) \
    -b $(SERCOMM_ROOTFS0_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn1
  cat $@.hdrkrn1 $(IMAGE_KERNEL) > $@.krn1
  # 
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $@.krn1 \
		--output-file $@.kernel \
		--part-name kernel \
		--part-version $(SERCOMM_SWVER)
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $@ \
		--output-file $@.rootfs \
		--part-name rootfs \
		--part-version $(SERCOMM_SWVER)

  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL1_OFFSET) \
    -b $(SERCOMM_ROOTFS1_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn2
  cat $@.hdrkrn2 $(IMAGE_KERNEL) > $@.krn2

	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $@.krn1 \
		--output-file $@.kernel2 \
		--part-name kernel2 \
		--part-version $(SERCOMM_SWVER)
	$(TOPDIR)/scripts/sercomm-partition-tag.py \
		--input-file $@ \
		--output-file $@.rootfs2 \
		--part-name rootfs2 \
		--part-version $(SERCOMM_SWVER)
  cat $@.kernel $@.rootfs $@.kernel2 $@.rootfs2 > $@.frst

  # 
	gzip -f -9n -c $@.frst > $@.gz

  # 
  $(STAGING_DIR_HOST)/bin/sercomm_tag_pid \
    -a $(SERCOMM_0x0str) \
    -b $(SERCOMM_0x04str) \
    -c $(SERCOMM_HWID) \
    -d $(SERCOMM_0x10str) \
    -g $(SERCOMM_SWVER) \
    -o $@.pid
  dd if=/dev/zero bs=1 count=16 seek=$$((0x70)) of=$@.pid conv=notrunc
  printf '\x0a' | dd of=$@.pid bs=1 seek=$$((0x70)) conv=notrunc

	$(TOPDIR)/scripts/sercomm-payload.py \
		--input-file $@.gz \
		--output-file $@.scnd \
		--pid "$$(cat $@.pid | od -t x1 -An -v | tr -d '\n')"
	$(TOPDIR)/scripts/sercomm-crypto.py \
		--input-file $@.scnd \
		--key-file $@.key \
		--output-file $@.hdrenc \
		--version $(SERCOMM_SWVER)
	$(STAGING_DIR_HOST)/bin/openssl enc -md md5 -aes-256-cbc \
		-in $@.scnd -out $@.enc \
		-K `cat $@.key` \
		-iv 00000000000000000000000000000000
  cat $@.hdrenc $@.enc > $@.new
	mv $@.new $@
	rm -f $@.hdrkrn1 $@.krn1 $@.kernel $@.rootfs $@.hdrkrn2 $@.krn2 \
    $@.kernel2 $@.rootfs2 $@.frst $@.gz $@.pid $@.scnd \
    $@.key $@.hdrenc $@.enc
endef

define Build/sercomm-tag-factory-type-B-pro
  $(STAGING_DIR_HOST)/bin/sercomm_tag_pid \
    -a $(SERCOMM_0x0str) \
    -c $(SERCOMM_HWID) \
    -g $(SERCOMM_SWVER) \
    -o $@.pid

  printf 11223344556677889900112233445566 | sed 's/../\\x&/g' | \
		xargs -d . printf | dd of=$@.footer conv=notrunc 2>/dev/null
  
  dd if=$@.pid of=$@.hdrfactory conv=notrunc 2>/dev/null
  printf $$(stat -c%s $(IMAGE_KERNEL)) | dd seek=$$((0x70)) of=$@.hdrfactory \
    bs=1 conv=notrunc 2>/dev/null
  printf $$(stat -c%s $@) | dd seek=$$((0x80)) of=$@.hdrfactory bs=1 \
		conv=notrunc 2>/dev/null
  printf $$(stat -c%s $@.footer) | dd seek=$$((0x90)) of=$@.hdrfactory bs=1 \
		conv=notrunc 2>/dev/null
  cat $(IMAGE_KERNEL) $@ $@.footer | $(MKHASH) md5 | awk '{print $$1}' | \
		tr -d '\n' | dd seek=$$((0x1e0)) of=$@.hdrfactory bs=1 \
		conv=notrunc 2>/dev/null
  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL0_OFFSET) \
    -b $(SERCOMM_ROOTFS0_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn1
  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL1_OFFSET) \
    -b $(SERCOMM_ROOTFS1_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn2
  cat $@.hdrfactory $@.hdrkrn1 $@.hdrkrn2 $(IMAGE_KERNEL) $@ $@.footer > $@.new
  mv $@.new $@ ; rm -f $@.hdrfactory $@.hdrkrn1 $@.hdrkrn2 $@.footer $@.pid
endef

define Build/sercomm-tag-factory-type-B-turbo-plus
  $(STAGING_DIR_HOST)/bin/sercomm_tag_pid \
    -a $(SERCOMM_0x0str) \
    -c $(SERCOMM_HWID) \
    -g $(SERCOMM_SWVER) \
    -o $@.pid
  
  dd if=$@.pid of=$@.hdrfactory conv=notrunc 2>/dev/null
  printf $$(stat -c%s $(IMAGE_KERNEL)) | dd seek=$$((0x70)) of=$@.hdrfactory \
    bs=1 conv=notrunc 2>/dev/null
  printf $$(stat -c%s $@) | dd seek=$$((0x80)) of=$@.hdrfactory bs=1 \
		conv=notrunc 2>/dev/null
  cat $(IMAGE_KERNEL) $@ | $(MKHASH) md5 | awk '{print $$1}' | \
		tr -d '\n' | dd seek=$$((0x1e0)) of=$@.hdrfactory bs=1 \
		conv=notrunc 2>/dev/null
  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL0_OFFSET) \
    -b $(SERCOMM_ROOTFS0_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn1
  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL1_OFFSET) \
    -b $(SERCOMM_ROOTFS1_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn2
  cat $@.hdrfactory $@.hdrkrn1 $@.hdrkrn2 $(IMAGE_KERNEL) $@ > $@.new
  mv $@.new $@ ; rm -f $@.hdrfactory $@.hdrkrn1 $@.hdrkrn2 $@.pid
endef

define Build/sercomm-tag-factory-type-AB
  $(STAGING_DIR_HOST)/bin/sercomm_tag_pid \
    -a $(SERCOMM_0x0str) \
    -c $(SERCOMM_HWID) \
    -d $(SERCOMM_0x10str) \
    -g $(SERCOMM_SWVER) \
    -o $@.pid
  dd if=$@.pid of=$@.hdrfactory conv=notrunc 2>/dev/null
  printf $$(stat -c%s $(IMAGE_KERNEL)) | dd seek=$$((0x70)) of=$@.hdrfactory bs=1 \
		conv=notrunc 2>/dev/null
  printf $$(stat -c%s $@) | dd seek=$$((0x80)) of=$@.hdrfactory bs=1 \
		conv=notrunc 2>/dev/null
  cat $(IMAGE_KERNEL) $@ | $(MKHASH) md5 | awk '{print $$1}' | \
		tr -d '\n' | dd seek=$$((0x1e0)) of=$@.hdrfactory bs=1 \
		conv=notrunc 2>/dev/null
  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL0_OFFSET) \
    -b $(SERCOMM_ROOTFS0_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn1
  $(STAGING_DIR_HOST)/bin/sercomm_tag_kernel \
    -a $(SERCOMM_KERNEL1_OFFSET) \
    -b $(SERCOMM_ROOTFS1_OFFSET) \
    -c $(IMAGE_KERNEL) \
    -d $@ \
    -e $@.hdrkrn2
  cat $@.hdrfactory $@.hdrkrn1 $@.hdrkrn2 $(IMAGE_KERNEL) $@ > $@.scnd
	$(TOPDIR)/scripts/sercomm-crypto.py \
		--input-file $@.scnd \
		--key-file $@.key \
		--output-file $@.hdrenc \
		--version $(SERCOMM_SWVER)
	$(STAGING_DIR_HOST)/bin/openssl enc -md md5 -aes-256-cbc \
		-in $@.scnd -out $@.enc \
		-K `cat $@.key` \
		-iv 00000000000000000000000000000000
  cat $@.hdrenc $@.enc > $@.new
	mv $@.new $@
	rm -f $@.hdrfactory $@.hdrkrn1 $@.hdrkrn2 $@.scnd \
    $@.key $@.hdrenc $@.enc $@.pid
endef

define Device/sercomm-common-temp
  $(Device/dsa-migration)
  BLOCKSIZE := 128k
  PAGESIZE := 2KiB
  UBINIZE_OPTS := -E 5
  LZMA_TEXT_START := 0x82800000
  LOADER_TYPE := bin
  KERNEL := $(KERNEL_DTB) | loader-kernel | lzma | uImage lzma
  IMAGE/sysupgrade.bin := append-ubi | \
    sercomm-tag-header-kernel $$$$(SERCOMM_KERNEL0_OFFSET) $$$$(SERCOMM_ROOTFS0_OFFSET) | \
    sysupgrade-tar kernel=$$$$@ | append-metadata
  DEVICE_VENDOR := Sercomm
  SERCOMM_0x0str := 0001
  SERCOMM_HWID = $$(DEVICE_VARIANT)
  # Для удобства внутреннего пользования
  IMAGES += kernel0.bin rootfs0.bin
  IMAGE/kernel0.bin := append-ubi | \
    sercomm-tag-header-kernel $$$$(SERCOMM_KERNEL0_OFFSET) $$$$(SERCOMM_ROOTFS0_OFFSET)
  IMAGE/rootfs0.bin := append-ubi | check-size
endef

define Build/test-test
# Debug
# Проверка переменных
	echo DEVICE_VARIANT= $(DEVICE_VARIANT); \
	echo SERCOMM_HWID= $(SERCOMM_HWID); \
	echo SERCOMM_HWID2= $(SERCOMM_HWID2); \
	echo SERCOMM_HWID3= $(SERCOMM_HWID3); \
	echo SERCOMM_HWID4= $(SERCOMM_HWID4)
  cat no.file > tmp.no.file
endef

define Device/sercomm-s1500-common-temp
  $(Device/sercomm-common-temp)
  DEVICE_MODEL := S1500
  KERNEL_SIZE := 4m
  IMAGE_SIZE := 30m
  IMAGES += factory.img
  IMAGE/factory.img := append-ubi | sercomm-tag-factory-type-B-pro
  SERCOMM_KERNEL0_OFFSET := 0x1700100
  SERCOMM_ROOTFS0_OFFSET := 0x1f00000
  SERCOMM_KERNEL1_OFFSET := 0x1b00100
  SERCOMM_ROOTFS1_OFFSET := 0x3d00000
  DEVICE_PACKAGES := kmod-mt7603 kmod-mt7615e kmod-mt7615-firmware kmod-usb3 \
  uboot-envtools
endef

define Device/sercomm-s3-common-temp
  $(Device/sercomm-common-temp)
  DEVICE_MODEL := S3
  KERNEL_SIZE := 6m
  IMAGE_SIZE := 32m
  KERNEL_LOADADDR := 0x81001000
  IMAGES += factory.img
  IMAGE/factory.img := append-ubi | sercomm-tag-factory-type-A
  SERCOMM_KERNEL0_OFFSET := 0x400100
  SERCOMM_ROOTFS0_OFFSET := 0x1000000
  SERCOMM_KERNEL1_OFFSET := 0xA00100
  SERCOMM_ROOTFS1_OFFSET := 0x3000000
  DEVICE_PACKAGES := kmod-mt7603 kmod-mt7615e kmod-mt7615-firmware kmod-usb3 \
  uboot-envtools
endef

define Device/beeline_smartbox-pro
  $(Device/sercomm-s1500-common-temp)
  SERCOMM_SWVER := 2020
  DEVICE_VARIANT := AWI
  DEVICE_ALT0_VENDOR := Beeline
  DEVICE_ALT0_MODEL := SmartBox PRO
  DEVICE_PACKAGES := kmod-mt76x2 kmod-usb3 uboot-envtools
endef
TARGET_DEVICES += beeline_smartbox-pro

define Device/wifire_s1500-nbn
  $(Device/sercomm-s1500-common-temp)
  IMAGE_SIZE := 46m
  IMAGE/factory.img := append-ubi | sercomm-tag-factory-type-AB
  SERCOMM_ROOTFS1_OFFSET := 0x4d00000
  SERCOMM_0x10str := 0001
  SERCOMM_SWVER := 2015
  DEVICE_VARIANT := BUC
  DEVICE_ALT0_VENDOR := WiFire
  DEVICE_ALT0_MODEL := Sercomm S1500
  DEVICE_ALT0_VARIANT := NBN
  DEVICE_PACKAGES := kmod-mt76x2 kmod-usb3 uboot-envtools
endef
TARGET_DEVICES += wifire_s1500-nbn

define Device/beeline_smartbox-giga
  $(Device/sercomm-common-temp)
  KERNEL_SIZE := 6m
  IMAGE_SIZE := 24m
  KERNEL_LOADADDR := 0x81001000
  SERCOMM_KERNEL0_OFFSET := 0x400100
  SERCOMM_ROOTFS0_OFFSET := 0x1000000
  SERCOMM_KERNEL1_OFFSET := 0xA00100
  SERCOMM_ROOTFS1_OFFSET := 0x2800000
  SERCOMM_0x04str := 0100
  SERCOMM_SWVER := 2002
  IMAGES += factory.img
  IMAGE/factory.img := append-ubi | sercomm-tag-factory-type-A-hack
  # По аналогии разбить на части конвеер
  #IMAGE/factory01.img := append-ubi | sercomm-part-tag rootfs | \
	#sercomm-prepend-tagged-kernel kernel | gzip | sercomm-payload | \
	#sercomm-crypto
  DEVICE_MODEL := S2
  DEVICE_VARIANT := DBE
  DEVICE_ALT0_VENDOR := Beeline
  DEVICE_ALT0_MODEL := SmartBox GIGA
  DEVICE_PACKAGES := kmod-mt7603 kmod-mt7615e kmod-mt7663-firmware-ap \
	kmod-usb3 uboot-envtools
endef
TARGET_DEVICES += beeline_smartbox-giga

define Device/beeline_smartbox-turbo
  $(Device/sercomm-s3-common-temp)
  SERCOMM_0x04str := 0200
  SERCOMM_SWVER := 1004
  DEVICE_VARIANT := DF3
  DEVICE_ALT0_VENDOR := Beeline
  DEVICE_ALT0_MODEL := SmartBox TURBO
endef
TARGET_DEVICES += beeline_smartbox-turbo

define Device/beeline_smartbox-turbo-plus
  $(Device/sercomm-s3-common-temp)
  IMAGE/factory.img := append-ubi | sercomm-tag-factory-type-B-turbo-plus
  SERCOMM_SWVER := 2010
  DEVICE_VARIANT := CQR
  DEVICE_ALT0_VENDOR := Beeline
  DEVICE_ALT0_MODEL := SmartBox TURBO+
endef
TARGET_DEVICES += beeline_smartbox-turbo-plus

define Device/sercomm_s3
  $(Device/sercomm-s3-common-temp)
  SERCOMM_SWVER := 3005
  DEVICE_VARIANT := DDK
  DEVICE_ALT0_VENDOR := Etisalat
  DEVICE_ALT0_MODEL := Sercomm S3 AC2100
endef
TARGET_DEVICES += sercomm_s3

define Device/sercomm_rt-sf-1
  $(Device/sercomm-s3-common-temp)
  SERCOMM_0x04str := 0110
  SERCOMM_SWVER := 1026
  DEVICE_VARIANT := DKG
  DEVICE_ALT0_VENDOR := Rostelecom 
  DEVICE_ALT0_MODEL := Sercomm RT-SF-1
endef
TARGET_DEVICES += sercomm_rt-sf-1

define Device/sercomm_rt-fe-1
  $(Device/sercomm-s3-common-temp)
  SERCOMM_0x04str := 1300
  SERCOMM_SWVER := 2019
  DEVICE_VARIANT := CX4
  DEVICE_ALT0_VENDOR := Rostelecom 
  DEVICE_ALT0_MODEL := Sercomm RT-FE-1
endef
TARGET_DEVICES += sercomm_rt-fe-1
