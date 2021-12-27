# TEST
# for device's SerComm

# Sercomm kernel signature
define Build/sercomm-tag-kernel
	dd if=/dev/zero count=$((0x100)) iflag=count_bytes 2>/dev/null | \
		tr "\0" "\377" > $@
	#$(KERNEL_IMG)
	#$(KERNEL_OFFSET)
	#$(KERNEL_SIZE)

	# Write tag header data
	# 0x04 - Address Kernel + Size Kernel
	printf "%8x" $(($KERNEL_OFFSET + $KERNEL_SIZE)) | sed 's/ /0/g' | \
	awk '{for (i=7;i>=1;i=i-2) printf "%s%s", substr($1,i,2), (i>1?"":"")}'| \
	sed 's/../\\x&/g' | xargs -d . printf | \
	dd seek=$((0x04)) of=$@ bs=1 conv=notrunc 2>/dev/null
	# 0x0c - ? Magic constant (0x2ffffff)
	printf '\x2' | \
	dd seek=$((0x0c)) of=$@ bs=1 conv=notrunc 2>/dev/null

	# Write kernel data
	# 0x10 - Address Kernel
	printf "%8x" $KERNEL_OFFSET | sed 's/ /0/g' | \
	awk '{for (i=7;i>=1;i=i-2) printf "%s%s", substr($1,i,2), (i>1?"":"")}'| \
	sed 's/../\\x&/g' | xargs -d . printf | \
	dd seek=$((0x10)) of=$@ bs=1 conv=notrunc 2>/dev/null
	# 0x14 - Size Kernel
	printf "%8x" $KERNEL_SIZE | sed 's/ /0/g' | \
	awk '{for (i=7;i>=1;i=i-2) printf "%s%s", substr($1,i,2), (i>1?"":"")}'| \
	sed 's/../\\x&/g' | xargs -d . printf | \
	dd seek=$((0x14)) of=$@ bs=1 conv=notrunc 2>/dev/null
	# 0x18 - CRC32 Kernel
	dd if=$KERNEL_IMG 2>/dev/null | \
	gzip -c | tail -c 8 | od -An -tx4 -N4 --endian=big | tr -d ' \n' | \
	sed 's/../\\x&/g' | xargs -d . printf | \
	dd seek=$((0x18)) of=$@ bs=1 conv=notrunc 2>/dev/null
	# 0x1c - Zeros
	printf "%8x" 0x0 | sed 's/ /0/g' | \
	sed 's/../\\x&/g' | xargs -d . printf | \
	dd seek=$((0x1c)) of=$@ bs=1 conv=notrunc 2>/dev/null

	# Write rootfs data
	# 0x28 - Address RootFS
	write_tag 0x28 $(trim_hx $ROOTFS_OFFSET | swap_hx)
	# 0x2c - Size RootFS
	write_tag 0x2c $(printf "%x\n" $(fsize $ROOTFS_IMG) | pad_zeros | swap_hx)
	# 0x30 - CRC32 RootFS
	write_tag 0x30 $(chksum $ROOTFS_IMG)
	# 0x34 - Zeros
	write_tag 0x34 $(trim_hx 0x0)

	# 0x08 - Header checksum. 0xffffffff for hdr crc32 calc
	write_tag 0x08 $(chksum $FILE_TMP)
	# 0x00 - Sercomm Signature (0x53657200), 0xffffffff for hdr crc32 calc
	write_tag 0x00 $(trim_hx 0x53657200)
endef

# Sercomm firmware factory signature footer
define Build/sercomm-tag-footer
	printf 11223344556677889900112233445566 | sed 's/../\\x&/g' | \
	xargs -d . printf | dd of=$@ conv=notrunc 2>/dev/null
endef