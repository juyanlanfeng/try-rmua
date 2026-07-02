FROM adamrehn/ue4-runtime:noaudio

USER root
# 国内网络:把 ubuntu apt 源换成中科大镜像(直连,快且稳;代理对明文 HTTP apt 不可靠)
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g; s@//security.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list
RUN echo 'Etc/UTC' > /etc/timezone && \
    ln -s /usr/share/zoneinfo/Etc/UTC /etc/localtime && \
    apt-get update && \
    apt-get install -q -y --no-install-recommends tzdata && \
    rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -q -y --no-install-recommends \
    dirmngr \
    gnupg2 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*
# 国内网络:ROS 源用中科大 HTTP 镜像(packages.ros.org 国内连不上;用 HTTP 免去 ca-certificates 依赖),key 仍从 keyserver.ubuntu.com 直连取
RUN echo "deb http://mirrors.ustc.edu.cn/ros/ubuntu focal main" > /etc/apt/sources.list.d/ros1-latest.list
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV ROS_DISTRO noetic
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-noetic-ros-core=1.5.0-1* \
    unzip
RUN apt-get install -y --no-install-recommends iproute2 iputils-ping\
    && rm -rf /var/lib/apt/lists/* 

ADD start.bash /usr/local/
RUN chmod +x /usr/local/start.bash
# 使用本地 Build/(simulator_12.0.0.5),不再从阿里云下载旧版 zip
# 注意:ADD <目录> 复制的是目录内容,故 Build/LinuxNoEditor -> /usr/local/LinuxNoEditor
ADD Build/LinuxNoEditor /usr/local/LinuxNoEditor
ADD settings.json /usr/local/LinuxNoEditor/RMUA/Binaries/Linux/

RUN chmod +x /usr/local/LinuxNoEditor/RMUA/Binaries/Linux/RMUA-Linux-Shipping
USER ue4
ENTRYPOINT [ "/usr/local/start.bash" ]
