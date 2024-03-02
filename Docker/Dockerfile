#基础镜像
FROM ubuntu:22.04

#维护者
MAINTAINER bingo1991

RUN sed -i -r 's#http://(archive|security).ubuntu.com#http://mirrors.ustc.edu.cn#g' /etc/apt/sources.list \
  && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
  && echo 'Asia/Shanghai' >/etc/timezone

RUN apt update \
  && apt install --no-install-recommends -y locales apt-utils dialog binfmt-support qemu-user-static \
     make sudo cpio bzip2 net-tools curl wget language-selector-common \
  && apt-get autoremove \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN localedef -c -f UTF-8 -i en_US en_US.UTF8

ENV LANG en_US.UTF8
