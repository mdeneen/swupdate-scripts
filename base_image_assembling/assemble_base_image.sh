#!/usr/bin/bash

function generate_mbr_dualslot()
{
	local PT_DISKLABEL=$1
	local PT_FILESIZE=$2

	if [ -z "${PT_DISKLABEL}" ]; then
		echo "Error: please specify an disk label for MBR!"
		exit 1
	fi

	if [ -z "${PT_FILESIZE}" ]; then
        echo "Error: please specify a file size for MBR!"
        exit 1
	fi

	truncate -s ${PT_FILESIZE} ${PT_DISKLABEL}
	if [ $? != 0 ]; then
		echo "truncate to ${PT_FILESIZE} on ${PT_DISKLABEL} failed!"
		exit -1
	fi

	sudo parted -s ${PT_DISKLABEL} mklabel msdos
	if [ $? != 0 ]; then
		echo "mklabel msdos on ${PT_DISKLABEL} failed!"
		exit -1
	fi

	for each_item in $IMAGE_MBR_PT_STRUCT; do
		local pt_start=$(echo $each_item | cut -d: -f2)
		local pt_end=$(echo $each_item | cut -d: -f3)
		local pt_fs=$(echo $each_item | cut -d: -f4)
		sudo parted ${PT_DISKLABEL} unit MiB mkpart primary ${pt_fs} ${pt_start}  ${pt_end}
		if [ $? != 0 ]; then
			echo "part ${pt_fs} from ${pt_start} to ${pt_end} on ${PT_DISKLABEL} failed!"
			exit -1
		fi
	done
	sudo parted ${PT_DISKLABEL} unit MiB print

	# MBR is 512 bytes
	truncate -s ${IMAGE_MBR_LENGTH} ${PT_DISKLABEL}
	if [ $? != 0 ]; then
		echo "truncate to ${IMAGE_MBR_SIZE} on ${PT_DISKLABEL} failed!"
		exit -1
	fi
}

function print_help()
{
	echo "$0 - generate update image"
	echo "-o specify output image name. Default is swu_<SLOT>_rescue_<soc>_<storage>_<date>.sdcard"
	echo "-d enable double slot copy. Default is single slot copy."
	echo "-e enable emmc. Default is sd."
	echo "-b soc name. Currently, imx8mm and imx6ull are supported."
	echo "-m Only regenerate or overwrite MBR. This option can be used to generate MBR individually."
	echo "   Suppose that we don't need to generate MBR every time. Normally we only need to generate it once."
	echo "-h print this help."
}

WRK_DIR="$(pwd)"
#CUR_DATE=$(date "+%Y%m%d-%H%M%S")
CUR_DATE=$(date "+%Y%m%d")

SUPPORTED_SOC="
imx8mm
imx6ull
"

TMP_BIN_FILE="./tmp.bin"

OUTPUT_IMAGE_NAME=""
DOUBLESLOT_FLAG=false
COPY_MODE="singlecopy"
STORAGE_EMMC_FLAG=false
STORAGE_DEVICE="sd"
PT_SIZE=''
GENERATE_MBR_ONLY_FLAG=false

while getopts "o:deb:mh" arg; do
	case $arg in
		o)
			OUTPUT_IMAGE_NAME=$OPTARG
			;;
		d)
			DOUBLESLOT_FLAG=true
			COPY_MODE="doublecopy"
			;;
		e)
			STORAGE_EMMC_FLAG=true
			STORAGE_DEVICE="emmc"
			;;
		b)
			SOC=$OPTARG
			;;
		m)
			GENERATE_MBR_ONLY_FLAG=true
			;;
		h)
			print_help
			exit 0
			;;
		?)
			echo "Error: unkonw argument!"
			exit 1
			;;
	esac
done

if [ -z "${SOC}" ]; then
	echo "No SOC specified!"
	exit 1
else
	VALID_SOC_FLAG=false
	for each_item in $SUPPORTED_SOC; do
		if [ x${each_item} == x${SOC} ]; then
			VALID_SOC_FLAG=true
		fi
	done
	if [ x${VALID_SOC_FLAG} == x"${false}" ]; then
		echo "Not supported SoC: ${SOC}"
	fi
fi

SOC_ASSEMBLE_SETTING_FILE="cfg_${SOC}.cfg"
source ${WRK_DIR}/../boards/${SOC_ASSEMBLE_SETTING_FILE}
source ${WRK_DIR}/../utils/utils.sh

if [ -z "${OUTPUT_IMAGE_NAME}" ]; then
	echo "No output image name specified! Use default name!"
	OUTPUT_IMAGE_NAME=swu_${COPY_MODE}_rescue_${SOC_NAME}_${STORAGE_DEVICE}_${CUR_DATE}.sdcard
fi
echo "Output image name is: $OUTPUT_IMAGE_NAME"
if test -e ./$OUTPUT_IMAGE_NAME; then
	echo -n "Delete existing $OUTPUT_IMAGE_NAME..."
	rm ./$OUTPUT_IMAGE_NAME
	echo "DONE"
fi

echo -n ">>>> Check MBR file..."
IMAGE_MBR_SIZE=$(echo ${IMAGE_MBR} | cut -d: -f3)
MBR_FILENAME=$(basename ${IMAGE_MBR_PATH})
MBR_FILEDIR=$(dirname ${IMAGE_MBR_PATH})
if [ x$GENERATE_MBR_ONLY_FLAG == xtrue ]; then
	echo ">>>> Regenerate or overwrite MBR..."
	if [ -e ${IMAGE_MBR_PATH} ]; then
		echo "Delete existed MBR ${IMAGE_MBR_PATH}"
		rm ${IMAGE_MBR_PATH}
	fi
	echo "Generating MBR ${IMAGE_MBR_PATH}"
	cd $MBR_FILEDIR
	generate_mbr_dualslot $MBR_FILENAME $IMAGE_MBR_SIZE
	cd -
	echo "DONE"
	exit 0
else
	if [ ! -e ${IMAGE_MBR_PATH} ]; then
		echo -n "\nNo MBR file, will generate MBR..."
		cd $MBR_FILEDIR
		generate_mbr_dualslot $MBR_FILENAME $IMAGE_MBR_SIZE
		cd -
	fi
fi
echo "DONE"

echo -n ">>>> Check slota boot partition mirror..."
BOOT_PT=$(echo $SLOTA_BOOT_PT | cut -d: -f1)
if [ ! -e ${BOOT_PT} ]; then
	echo ""
	echo -n "No slata boot partition mirror, generate..."
	cd $BOOT_PT_DIR
	calculate_pt_size $SLOTA_BOOT_PT PT_SIZE
	truncate -s ${PT_SIZE} ${BOOT_PT}
	cd -
fi
echo "DONE"

echo -n ">>>> Check slotb boot partition mirror..."
BOOT_PT=$(echo $SLOTB_BOOT_PT | cut -d: -f1)
if [ ! -e ${BOOT_PT} ]; then
	echo ""
	echo -n "\nNo slatb boot partition mirror, generate..."
	calculate_pt_size $SLOTB_BOOT_PT PT_SIZE
	truncate -s ${PT_SIZE} ${BOOT_PT}
fi
echo "DONE"

echo -n ">>>> Check slota link..."
if test ! -d ./slota; then
	echo "ERROR: need to link slata to yocto image deploy directory!"
	exit 1
fi
echo "DONE"

echo -n ">>>> Check slotb link..."
if test ! -d ./slotb; then
	echo "ERROR: need to link slatb to yocto image deploy directory!"
	exit 1
fi
echo "DONE"

# assemble images
touch $OUTPUT_IMAGE_NAME

# 1. assemble header
echo ">>>> Making header..."
for each_item in $IMAGES_HEADER; do
	img_file=$(echo $each_item | cut -d: -f1)
	pad_start=$(echo $each_item | cut -d: -f2)
	pad_end=$(echo $each_item | cut -d: -f3)
	touch $TMP_BIN_FILE
	generate_padding_file $pad_start $img_file $pad_end $TMP_BIN_FILE
	if [ $? != 0 ]; then
		rm -f $TMP_BIN_FILE
		exit 1
	fi
	cat $TMP_BIN_FILE >> $OUTPUT_IMAGE_NAME
	rm -f $TMP_BIN_FILE
done
echo "DONE"

# 2. assemble swupdate
echo ">>>> Making swupdate..."
for each_item in $IMAGES_SWUPDATE; do
	img_file=$(echo $each_item | cut -d: -f1)
	pad_start=$(echo $each_item | cut -d: -f2)
	pad_end=$(echo $each_item | cut -d: -f3)
	touch $TMP_BIN_FILE
	generate_padding_file $pad_start $img_file $pad_end $TMP_BIN_FILE
	if [ $? != 0 ]; then
		rm -f $TMP_BIN_FILE
		exit 1
	fi
	cat $TMP_BIN_FILE >> $OUTPUT_IMAGE_NAME
	rm -f $TMP_BIN_FILE
done
echo "DONE"

# 3. assemble slota
echo ">>>> Making slota..."
BOOT_PT_PATH=$(echo $SLOTA_BOOT_PT | cut -d: -f1)
copy_images_to_boot_pt $BOOT_PT_PATH slota
ROOTFS_IMG=$(echo $SLOTA_ROOTFS | cut -d: -f1)
if [ ! -e $ROOTFS_IMG ]; then
	echo "SLOTA ROOTFS image not found!"
	exit -1
fi
calculate_pt_size $SLOTA_ROOTFS PT_SIZE
truncate -s $PT_SIZE $ROOTFS_IMG
e2fsck -f $ROOTFS_IMG
resize2fs $ROOTFS_IMG
for each_item in $SLOTA_IMAGES; do
	item_path=$(echo $each_item | cut -d: -f1)
	cat $item_path >> $OUTPUT_IMAGE_NAME
done
echo "DONE"

# 4. assemble slotb
if [ x$DOUBLESLOT_FLAG == x"true" ]; then
	echo ">>>> Making slotb..."
	BOOT_PT_PATH=$(echo $SLOTB_BOOT_PT | cut -d: -f1)
	copy_images_to_boot_pt $BOOT_PT_PATH slotb
	ROOTFS_IMG=$(echo $SLOTB_ROOTFS | cut -d: -f1)
	if [ ! -e $ROOTFS_IMG ]; then
		echo "SLOTB ROOTFS image not found!"
		exit -1
	fi
	calculate_pt_size $SLOTB_ROOTFS PT_SIZE
	truncate -s $PT_SIZE $ROOTFS_IMG
	e2fsck -f $ROOTFS_IMG
	resize2fs $ROOTFS_IMG
	for each_item in $SLOTB_IMAGES; do
		item_path=$(echo $each_item | cut -d: -f1)
		cat $item_path >> $OUTPUT_IMAGE_NAME
	done
	echo "DONE"
fi

echo "==========================================================================="
echo "Create base image $OUTPUT_IMAGE_NAME successfully"
echo "==========================================================================="

