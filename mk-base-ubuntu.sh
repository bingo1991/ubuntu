#!/bin/bash -e

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

ARCH='arm64'
TARGET_ROOTFS_DIR="binary"
UBUNTU_BASE_VER="22.04.4"

echo -e "\033[47;36m clean directory 'binary'...... \033[0m"
sudo rm -rf $TARGET_ROOTFS_DIR/

if [ ! -d $TARGET_ROOTFS_DIR ] ; then
	echo -e "\033[47;36m create directory 'binary'...... \033[0m"
	sudo mkdir -p $TARGET_ROOTFS_DIR

	if [ ! -e ubuntu-base-$UBUNTU_BASE_VER-base-$ARCH.tar.gz ]; then
		echo -e "\033[47;36m wget ubuntu-base-"$UBUNTU_BASE_VER"-base-"$ARCH".tar.gz \033[0m"
		wget -c http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-$UBUNTU_BASE_VER-base-$ARCH.tar.gz
	else
		echo -e "\033[47;36m use existed ubuntu-base-"$UBUNTU_BASE_VER"-base-"$ARCH".tar.gz \033[0m"
	fi
	
	echo -e "\033[47;36m extracting ubuntu-base-"$UBUNTU_BASE_VER"-base-"$ARCH".tar.gz...... \033[0m"
	sudo tar -xzf ubuntu-base-$UBUNTU_BASE_VER-base-$ARCH.tar.gz -C $TARGET_ROOTFS_DIR/
	sudo cp -b /etc/resolv.conf $TARGET_ROOTFS_DIR/etc/resolv.conf
	sudo cp sources.list $TARGET_ROOTFS_DIR/etc/apt/sources.list
	if [ ! -e /usr/bin/qemu-aarch64-static ]; then
		echo -e "\033[47;36m /usr/bin/qemu-aarch64-static does not exist! \033[0m"
		exit -1
	else
		sudo cp -b /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
	fi
fi

finish() {
	./ch-mount.sh -u $TARGET_ROOTFS_DIR
	echo -e "error exit"
	exit -1
}
trap finish ERR

echo -e "\033[47;36m Change root.................... \033[0m"

./ch-mount.sh -m $TARGET_ROOTFS_DIR

cat <<EOF | sudo chroot $TARGET_ROOTFS_DIR/

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install --no-install-recommends -y"

export LC_ALL=C.UTF-8
echo 'Asia/Shanghai' >/etc/timezone
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

apt-get -y update
apt-get upgrade -y

\${APT_INSTALL} \
	alsa-utils \
	apt-utils \
	bash-completion \
	build-essential \
	curl \
	device-tree-compiler \
	dialog \
	figlet \
	git \
	htop \
	libssl-dev \
	locales \
	neofetch \
	net-tools \
	openssh-server \
	python3-pip \
	rsync \
	rsyslog \
	sudo \
	toilet \
	tzdata \
	u-boot-tools \
	udev \
	usbutils \
	vim \
	wget \
	wpasupplicant

if [ "$TARGET" != "gnome-full" ]; then
	sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
	echo "LANG=en_US.UTF-8" >> /etc/default/locale

	# Generate locale
	locale-gen en_US.UTF-8

	# Export env vars
	echo "LC_ALL=en_US.UTF-8" >> /etc/environment
	echo "LANG=en_US.UTF-8" >> /etc/environment
	echo "LANGUAGE=en_US:en" >> /etc/environment

	echo "export LC_ALL=en_US.UTF-8" >> /etc/profile.d/en_US.sh
	echo "export LANG=en_US.UTF-8" >> /etc/profile.d/en_US.sh
	echo "export LANGUAGE=en_US:en" >> /etc/profile.d/en_US.sh
else
	echo -e "\033[47;36m Install Chinese fonts.................... \033[0m"
	\${APT_INSTALL} \
	language-pack-zh-hans language-pack-gnome-zh-hans \
	gnome-user-docs-zh-hans  \
	ttf-wqy-zenhei xfonts-intl-chinese fonts-noto-cjk-extra \
	fcitx fcitx-table fcitx-googlepinyin fcitx-pinyin fcitx-config-gtk

	# Uncomment zh_CN.UTF-8 for inclusion in generation
	sed -i 's/^# *\(zh_CN.UTF-8\)/\1/' /etc/locale.gen
	echo "LANG=zh_CN.UTF-8" >> /etc/default/locale

	# Generate locale
	locale-gen zh_CN.UTF-8

	# Export env vars
	echo "LC_ALL=zh_CN.UTF-8" >> /etc/environment
	echo "LANG=zh_CN.UTF-8" >> /etc/environment
	echo "LANGUAGE=zh_CN:zh:en_US:en" >> /etc/environment

	echo "export LC_ALL=zh_CN.UTF-8" >> /etc/profile.d/zh_CN.sh
	echo "export LANG=zh_CN.UTF-8" >> /etc/profile.d/zh_CN.sh
	echo "export LANGUAGE=zh_CN:zh:en_US:en" >> /etc/profile.d/zh_CN.sh
fi

if [ "$TARGET" != "lite" ]; then
	\${APT_INSTALL} \
	ubuntu-desktop-minimal ubuntu-session \
	gdm3 \
	glmark2-es2-wayland \
	gnome-bluetooth \
	gnome-tweaks \
	guvcview \
	laptop-detect \
	libdrm-tests \
	nautilus-extension-gnome-terminal \
	screenfetch \
	xwayland \
	yaru-theme-icon yaru-theme-gtk

	apt-get purge -y \
	firefox \
	gnome-session \
	ibus \
	imagemagick-6.q16 \
	libreoffice* \
	snapd \
	xserver-xorg-core \
	yelp
fi

apt-get autoremove --purge -y

HOST=rk35xx

# Create User
useradd -G sudo -m -s /bin/bash -d /home/user user

passwd user <<IEOF
12
12
IEOF
gpasswd -a user video
gpasswd -a user audio

passwd root <<IEOF
12
12
IEOF

# allow root login
sed -i '/pam_securetty.so/s/^/# /g' /etc/pam.d/login

# hostname
echo rk35xx > /etc/hostname

# set localtime
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# workaround 90s delay
services=(NetworkManager systemd-networkd)
for service in ${services[@]}; do
  systemctl mask ${service}-wait-online.service
done

# disbale the wire/nl80211
systemctl mask wpa_supplicant-wired@
systemctl mask wpa_supplicant-nl80211@
systemctl mask wpa_supplicant@

# Make systemd less spammy

sed -i 's/#LogLevel=info/LogLevel=warning/' \
  /etc/systemd/system.conf

sed -i 's/#LogTarget=journal-or-kmsg/LogTarget=journal/' \
  /etc/systemd/system.conf

# check to make sure sudoers file has ref for the sudo group
SUDOEXISTS="$(awk '$1 == "%sudo" { print $1 }' /etc/sudoers)"
if [ -z "$SUDOEXISTS" ]; then
  # append sudo entry to sudoers
  echo "# Members of the sudo group may gain root privileges" >> /etc/sudoers
  echo "%sudo	ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# make sure that NOPASSWD is set for %sudo
# expecially in the case that we didn't add it to /etc/sudoers
# just blow the %sudo line away and force it to be NOPASSWD
sed -i -e '
/\%sudo/ c \
%sudo	ALL=(ALL) NOPASSWD: ALL
' /etc/sudoers

apt-get clean
rm -rf /var/lib/apt/lists/*

sync

EOF

./ch-mount.sh -u $TARGET_ROOTFS_DIR

DATE=$(date +%Y%m%d)
echo -e "\033[47;36m Run tar pack ubuntu-base-$TARGET-$ARCH-$DATE.tar.gz \033[0m"
sudo tar zcf ubuntu-base-$TARGET-$ARCH-$DATE.tar.gz $TARGET_ROOTFS_DIR

# sudo rm $TARGET_ROOTFS_DIR -r

echo -e "\033[47;36m normal exit \033[0m"
