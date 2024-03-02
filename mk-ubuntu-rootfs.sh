#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"
ARCH=arm64

if [ ! $SOC ]; then
	echo "---------------------------------------------------------"
	echo "please enter soc number:"
	echo "请输入要构建CPU的序号:"
	echo "[0] Exit Menu"
	echo "[1] rk3566/rk3568"
	echo "[2] rk3588/rk3588s"
	echo "---------------------------------------------------------"
	read input

	case $input in
		0)
			exit;;
		1)
			SOC=rk356x
			;;
		2)
			SOC=rk3588
			;;
		*)
			echo 'input soc number error, exit !'
			exit;;
	esac
	echo -e "\033[47;36m set SOC=$SOC...... \033[0m"
fi

if [ ! $TARGET ]; then
	echo "---------------------------------------------------------"
	echo "please enter TARGET version number:"
	echo "请输入要构建的根文件系统版本:"
	echo "[0] Exit Menu"
	echo "[1] gnome"
	echo "[2] gnome-full"
	echo "[3] lite"
	echo "---------------------------------------------------------"
	read input

	case $input in
		0)
			exit;;
		1)
			TARGET=gnome
			;;
		2)
			TARGET=gnome-full
			;;
		3)
			TARGET=lite
			;;
		*)
			echo -e "\033[47;36m input TARGET version number error, exit ! \033[0m"
			exit;;
	esac
	echo -e "\033[47;36m set TARGET=$TARGET...... \033[0m"
fi

echo -e "\033[47;36m Building for $ARCH \033[0m"

if [ ! $VERSION ]; then
	VERSION="debug"
fi

echo -e "\033[47;36m Building for $VERSION \033[0m"

if [ ! -e ubuntu-base-"$TARGET"-$ARCH-*.tar.gz ]; then
	echo "\033[41;36m Run mk-base-ubuntu.sh first \033[0m"
	exit -1
fi

finish() {
	sudo umount $TARGET_ROOTFS_DIR/dev
	exit -1
}
trap finish ERR

echo -e "\033[47;36m Extract image \033[0m"
sudo rm -rf $TARGET_ROOTFS_DIR
sudo tar -xpf ubuntu-base-$TARGET-$ARCH-*.tar.gz

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rpf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

sudo mkdir -p $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpf packages/$ARCH/rktoolkit/*.deb $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpf packages/$ARCH/rkisp/*.deb $TARGET_ROOTFS_DIR/packages/install_packages
if [ "$SOC" == "rk356x" ]; then
	sudo cp -rpf packages/$ARCH/libmali/libmali-bifrost-g52* $TARGET_ROOTFS_DIR/packages/install_packages
	sudo cp -rpf packages/$ARCH/rkaiq/*rk3568_arm64.deb $TARGET_ROOTFS_DIR/packages/install_packages
elif [ "$SOC" == "rk3588" ]; then
	sudo cp -rpf packages/$ARCH/libmali/libmali-valhall-g610* $TARGET_ROOTFS_DIR/packages/install_packages
	sudo cp -rpf packages/$ARCH/rkaiq/*rk3588_arm64.deb $TARGET_ROOTFS_DIR/packages/install_packages
fi

# overlay folder
sudo cp -rpf overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder
sudo cp -rpf overlay-firmware/* $TARGET_ROOTFS_DIR/

# overlay-debug folder
# adb, video, camera  test file
if [ "$VERSION" == "debug" ]; then
	sudo cp -rpf overlay-debug/* $TARGET_ROOTFS_DIR/
fi

# hack the serial
sudo cp -f overlay/usr/lib/systemd/system/serial-getty@.service $TARGET_ROOTFS_DIR/lib/systemd/system/serial-getty@.service

# adb
if [ "$VERSION" == "debug" ]; then
	sudo cp -f overlay-debug/usr/local/share/adb/adbd $TARGET_ROOTFS_DIR/usr/bin/adbd
fi

echo -e "\033[47;36m Change root.....................\033[0m"
if [ -e "/usr/bin/qemu-aarch64-static" ]; then
	sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
else
	echo -e "\033[47;36m /usr/bin/qemu-aarch64-static does not exist...\033[0m"
	exit -1
fi

sudo mount -o bind /dev $TARGET_ROOTFS_DIR/dev

ID=$(stat --format %u $TARGET_ROOTFS_DIR)

cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

# Fixup owners
if [ "$ID" -ne 0 ]; then
	find / -user $ID -exec chown -h 0:0 {} \;
fi
for u in \$(ls /home/); do
	chown -h -R \$u:\$u /home/\$u
done

export LC_ALL=en_US.UTF-8

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod +x /etc/rc.local

export APT_INSTALL="apt-get install -f -y"

add-apt-repository ppa:liujianfeng1994/rockchip-multimedia -y
apt-get update -y
apt-get upgrade -y

echo -e "\033[47;36m ------ Install local packages ------ \033[0m"
apt install -f -y /packages/install_packages/*.deb

if [ "$TARGET" != "lite" ]; then
	echo -e "\033[47;36m ----- power management ----- \033[0m"
	\${APT_INSTALL} pm-utils triggerhappy bsdmainutils \
		chromium-browser ffmpeg mpv \
		gir1.2-gstreamer-1.0 gstreamer1.0-tools libgstreamer1.0-0 libgstreamer1.0-dev gstreamer1.0-rockchip1 \
		gir1.2-gst-plugins-base-1.0 gstreamer1.0-alsa gstreamer1.0-plugins-base gstreamer1.0-plugins-base-apps \
		libgstreamer-gl1.0-0 libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev librga2 librga-dev \
		rockchip-mpp-demos librockchip-mpp1 librockchip-mpp-dev librockchip-vpu0 v4l-utils libv4l-rkmpp 

	cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service
fi

apt --fix-broken install -y

if [ -e "/usr/lib/aarch64-linux-gnu" ] ; then
	echo -e "\033[47;36m ------- move rknpu2 --------- \033[0m"
	mv /packages/rknpu2/*.tar  /
fi

echo -e "\033[47;36m ------- Custom Script ------- \033[0m"
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
rm /lib/systemd/system/wpa_supplicant@.service

echo -e "\033[47;36m  ---------- Clean ----------- \033[0m"
rm -rf /home/$(whoami)
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/

EOF

sudo umount $TARGET_ROOTFS_DIR/dev

IMAGE_VERSION=$TARGET ./mk-image.sh 
