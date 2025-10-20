#!/bin/bash
set -Eeuo pipefail
on_err() {
  echo -e "\e[31m[错误] 第${BASH_LINENO[0]}行命令失败: ${BASH_COMMAND}\e[0m"
  echo -e "\e[31m请修复问题后重试。当前进度已写入 .liucheng。\e[0m"
  exit 1
}
trap on_err ERR
ARCH=$(uname -m)
if [[ "${ARCH}" == "x86_64" || "${ARCH}" == "amd64" ]]; then
    isx86=true
else
    isx86=false
fi
echo "当前架构为: ${ARCH}"
PWD=$(pwd)
Trainenv=false
echo "正在检查运行流程"
liucheng_num=0
if [ ! -f ".liucheng" ]; then
    echo "创建 .liucheng 文件"
    echo ${liucheng_num} >> .liucheng
else
    liucheng_num=$(cat .liucheng | grep -o '[0-9]*' | head -n 1)
    echo "当前流程到第${liucheng_num}步"
fi

# #docker安装
if [ ${liucheng_num} -eq 0 ]; then
    if [ -n "$(command -v docker)" ]; then
        echo "Docker已安装，跳过Docker安装步骤"
        liucheng_num=2
        echo ${liucheng_num} > .liucheng
    else
        sudo apt update
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        # curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        echo "添加 Docker GPG 密钥..."
        for mirror in "https://download.docker.com" "https://mirrors.aliyun.com/docker-ce" "https://mirrors.tuna.tsinghua.edu.cn/docker-ce"; do
            if curl -fsSL ${mirror}/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; then
                echo "Docker GPG 密钥添加成功 (使用 ${mirror})"
                docker_mirror=${mirror}
                break
            else
                echo "尝试 ${mirror} 失败，切换下一个镜像源..."
            fi
        done
        
        if [ -z "${docker_mirror:-}" ]; then
            echo "所有 Docker 镜像源都无法访问，请检查网络连接"
            exit 1
        fi
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt update
        sudo apt install -y docker-ce
        echo "60秒后将自动重启系统以写入docker用户权限..."
        echo "重启后继续执行该脚本"
        sudo groupadd docker 2>/dev/null 
        sudo usermod -aG docker $(whoami)
        newgrp docker
        liucheng_num=1
        echo ${liucheng_num} > .liucheng
        sleep 60
        sudo reboot
    fi
fi

# #docker代理安装
if [ ${liucheng_num} -eq 1 ]; then
  sudo mkdir -p /etc/docker
  sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.1panel.live",
    "https://docker.m.ixdev.cn",
    "https://hub.rat.dev",
    "https://image.cloudlayer.icu",
    "https://docker-registry.nmqu.com",
    "https://hub.amingg.com",
    "https://docker.amingg.com",
    "https://docker.hlmirror.com",
    "https://hub3.nat.tf",
    "https://docker.m.daocloud.io",
    "https://docker.367231.xyz",
    "https://hub.1panel.dev",
    "https://dockerproxy.cool",
    "https://docker.apiba.cn",
    "https://proxy.vvvv.ee"
  ]
}
EOF

  # 有 systemd 用 systemctl，否则尝试 service/信号；失败不致命
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl daemon-reload || true
    sudo systemctl restart docker || true
  else
    sudo service docker restart >/dev/null 2>&1 || sudo pkill -HUP dockerd >/dev/null 2>&1 || true
  fi

  liucheng_num=2
  echo ${liucheng_num} > .liucheng
fi

# NVIDIA docker安装
if [ ${liucheng_num} -eq 2 ]; then
    echo "正在检查 NVIDIA Container Toolkit 是否已安装..."
    # 检查 nvidia-container-toolkit 是否已安装
    if dpkg -l | grep  nvidia-container-toolkit && command -v nvidia-ctk &> /dev/null; then
        echo "NVIDIA Container Toolkit 已安装，跳过安装步骤"
        liucheng_num=3
        echo ${liucheng_num} > .liucheng
    else
        if ${isx86};then
            echo "NVIDIA Container Toolkit 未安装，开始安装..."
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
            && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
            sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list
            sudo apt-get update
            export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.17.8-1
            sudo apt-get install -y \
                nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
                nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
                libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
                libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}
            sudo apt install -y nvidia-container-toolkit
        else
             sudo apt-get update && sudo apt-get install  nvidia-container-toolkit
        fi
        sudo systemctl restart docker
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
        liucheng_num=3
        echo ${liucheng_num} > .liucheng
    fi
fi

if [ ${liucheng_num} -eq 3 ]; then
    echo "正在下载 osrf/ros:humble-desktop-full 镜像..."
    sudo docker pull osrf/ros:humble-desktop-full
    if [ $? -eq 0 ]; then
        echo "ROS humble 镜像下载成功"
    else
        echo "ROS humble 镜像下载失败，请检查网络连接"
        exit 1
    fi
    mkdir -p docker
    cd docker
    # 创建 Dockerfile
    cat > Dockerfile << 'EOF'
FROM osrf/ros:humble-desktop-full

# 使用固定的ubuntu用户（基础镜像已有）
# 确保以root用户身份运行包管理命令
USER root

# 安装额外的依赖包（如果需要）
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg2 lsb-release software-properties-common \
    sudo \
    locales \
    git \
    x11-apps \
    mesa-utils \
    vim \
    xterm \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 配置ubuntu用户的sudo权限
RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu && \
    usermod -aG sudo ubuntu && \
    echo "ubuntu ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu && \
    chmod 0440 /etc/sudoers.d/ubuntu && \
    visudo -c -f /etc/sudoers.d/ubuntu

# 添加额外的 sudoers 配置以确保无密码 sudo 正常工作
RUN echo "root ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    echo "%sudo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER ubuntu
WORKDIR /home/ubuntu
# 设置环境变量
ENV ROS_DISTRO=humble
ENV DISPLAY=:0

# 设置入口点
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
EOF
    cd ..
    liucheng_num=4
echo ${liucheng_num} > .liucheng

fi
# 拉取ubuntu22.04镜像
if [ ${liucheng_num} -eq 4 ]; then
    docker build --build-arg HOST_USER=$(whoami) --build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g) \
        -t leg_control2:latest ./docker/
    liucheng_num=5
    echo ${liucheng_num} > .liucheng
fi

# 读取镜像

if [ ${liucheng_num} -eq 5 ]; then
    echo "在创建 leg_control2 控制脚本..."
    cat > ~/.leg_control2_script << 'EOF'
xhost +local: >> /dev/null
echo "请输入指令控制leg_control2: 重启(r) 进入(e) 启动(s) 关闭(c) 删除(d) 测试(t) 创建容器(g):"
read choose
case $choose in
s) docker start leg_control2;;
r) docker restart leg_control2;;
e) docker exec -it leg_control2 /bin/bash;;
c) docker stop leg_control2;;
d) docker stop leg_control2 && docker rm leg_control2 && sudo rm -rf /home/$(whoami)/.fishros/bin/leg_control2;;
t) docker exec -it leg_control2  /bin/bash -c "source /ros_entrypoint.sh && ros2";;
g) docker run -d \
  --name leg_control2 \
  --gpus all \
  --privileged \
  --runtime=nvidia \
  -w /home/$(whoami) \
  -e DISPLAY=$DISPLAY \
  -e QT_X11_NO_MITSHM=1 \
  -e QT_QPA_PLATFORM=xcb \
  -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" \
  -e "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" \
  -e NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-all} \
  -e NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES:-all} \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR" \
  -v "/dev/dri:/dev/dri" \
  -v /home/$(whoami):/home/$(whoami) \
  --dns 8.8.8.8 \
  leg_control2:latest tail -f /dev/null
  docker network connect --ip 192.168.123.11 docker_macvlan_network leg_control2;;
esac
newgrp docker
EOF
    if ! grep -Fxq "alias lc2='bash ~/.leg_control2_script'" ~/.bashrc; then
        echo "alias lc2='bash ~/.leg_control2_script'" >> ~/.bashrc
    fi
    liucheng_num=6
    echo ${liucheng_num} > .liucheng
fi

if [ ${liucheng_num} -eq 6 ]; then
    mkdir -p legged_control2_ws/src
    cd legged_control2_ws/src
    git clone https://github.com/qiayuanl/unitree_bringup.git
    git clone https://github.com/davidzong1/motion_tracking_controller.git
    cd ../..
    if ${isx86};then
        if ${Trainenv};then
            git clone https://github.com/davidzong1/whole_body_tracking.git
        fi
    fi
    liucheng_num=7
    echo ${liucheng_num} > .liucheng
fi

if [ ${liucheng_num} -eq 7 ]; then
    echo -e "\e[31m请使用 'source ~/.bashrc' 命令来刷新环境\e[0m"
    echo -e "\e[31m请使用 'lc2' 命令来管理您的容器脚本\e[0m"
    echo -e "\e[31m第一次使用请在leg_control2选项中按 'g' 命令来创建容器\e[0m"
    echo -e "\e[31m/******** docker容器密码默认为没有密码 ********/\e[0m"
    echo -e "\e[31m/******** docker容器密码默认为没有密码 ********/\e[0m"
    echo -e "\e[31m/******** docker容器密码默认为没有密码 ********/\e[0m"
    echo -e "\e[31m/********** 进入容器后继续执行该脚本 **********/\e[0m"
    echo -e "\e[31m/********** 进入容器后继续执行该脚本 **********/\e[0m"
    echo -e "\e[31m/********** 进入容器后继续执行该脚本 **********/\e[0m"
    liucheng_num=8
    echo ${liucheng_num} > .liucheng
    exit 1
fi

if [ ${liucheng_num} -eq 8 ]; then
    if [ "$(id -un)" != "ubuntu" ]; then
        echo -e "\e[31m错误：当前用户为 '$(id -un)'，请切换到容器后再运行此脚本。\e[0m"
        echo "操作：使用 'leg_control2' 命令进入容器后再运行此脚本。"
        exit 1
    fi
    if ${isx86};then
        echo "deb [trusted=yes] https://github.com/qiayuanl/legged_buildfarm/raw/jammy-humble-amd64/ ./" | sudo tee /etc/apt/sources.list.d/qiayuanl_legged_buildfarm.list
        echo "yaml https://github.com/qiayuanl/legged_buildfarm/raw/jammy-humble-amd64/local.yaml humble" | sudo tee /etc/ros/rosdep/sources.list.d/1-qiayuanl_legged_buildfarm.list
        echo "deb [trusted=yes] https://github.com/qiayuanl/simulation_buildfarm/raw/jammy-humble-amd64/ ./" | sudo tee /etc/apt/sources.list.d/qiayuanl_simulation_buildfarm.list
        echo "yaml https://github.com/qiayuanl/simulation_buildfarm/raw/jammy-humble-amd64/local.yaml humble" | sudo tee /etc/ros/rosdep/sources.list.d/1-qiayuanl_simulation_buildfarm.list
        echo "deb [trusted=yes] https://github.com/qiayuanl/unitree_buildfarm/raw/jammy-humble-amd64/ ./" | sudo tee /etc/apt/sources.list.d/qiayuanl_unitree_buildfarm.list
        echo "yaml https://github.com/qiayuanl/unitree_buildfarm/raw/jammy-humble-amd64/local.yaml humble" | sudo tee /etc/ros/rosdep/sources.list.d/1-qiayuanl_unitree_buildfarm.list
    else
        echo "deb [trusted=yes] https://github.com/qiayuanl/legged_buildfarm/raw/jammy-humble-arm64/ ./" | sudo tee /etc/apt/sources.list.d/qiayuanl_legged_buildfarm.list
        echo "yaml https://github.com/qiayuanl/legged_buildfarm/raw/jammy-humble-arm64/local.yaml humble" | sudo tee /etc/ros/rosdep/sources.list.d/1-qiayuanl_legged_buildfarm.list
        echo "deb [trusted=yes] https://github.com/qiayuanl/simulation_buildfarm/raw/jammy-humble-arm64/ ./" | sudo tee /etc/apt/sources.list.d/qiayuanl_simulation_buildfarm.list
        echo "yaml https://github.com/qiayuanl/simulation_buildfarm/raw/jammy-humble-arm64/local.yaml humble" | sudo tee /etc/ros/rosdep/sources.list.d/1-qiayuanl_simulation_buildfarm.list
        echo "deb [trusted=yes] https://github.com/qiayuanl/unitree_buildfarm/raw/jammy-humble-arm64/ ./" | sudo tee /etc/apt/sources.list.d/qiayuanl_unitree_buildfarm.list
        echo "yaml https://github.com/qiayuanl/unitree_buildfarm/raw/jammy-humble-arm64/local.yaml humble" | sudo tee /etc/ros/rosdep/sources.list.d/1-qiayuanl_unitree_buildfarm.list
    else
    fi
    sudo apt-get update
    liucheng_num=9
    echo ${liucheng_num} > .liucheng
fi

if [ ${liucheng_num} -eq 9 ]; then
    sudo apt-get install ros-humble-legged-control-base -y
    sudo apt install ros-humble-mujoco-ros2-control -y
    sudo apt-get install ros-humble-unitree-description
    sudo apt-get install ros-humble-unitree-systems
    sudo apt-get install ros-humble-ros2-controllers ros-humble-rqt ros-humble-rqt-controller-manager ros-humble-rqt-publisher ros-humble-rviz2
    sudo apt install -y ros-humble-realsense2-camera ros-humble-realsense2-description
    rosdep install --from-paths src --ignore-src -r -y
    liucheng_num=10
    echo ${liucheng_num} > .liucheng
fi

if [ ${liucheng_num} -eq 10 ]; then
    cd legged_control2_ws
    colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelwithDebInfo --packages-up-to unitree_bringup
    colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelwithDebInfo --packages-up-to motion_tracking_controller
    set +u
    source install/setup.bash
    set -u
    cd ../
    liucheng_num=11
    echo ${liucheng_num} > .liucheng
fi


if [ "${liucheng_num}" -ge 11 ]; then
    cat > ./sim2sim.c << 'EOF'
#include <stdio.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <string.h>
#include <stdlib.h>
// 检查文件是否有指定后缀
int has_suffix(const char *filename, const char *suffix)
{
    size_t filename_len = strlen(filename);
    size_t suffix_len = strlen(suffix);

    if (filename_len < suffix_len)
    {
        return 0;
    }

    return strcmp(filename + filename_len - suffix_len, suffix) == 0;
}
// 执行终端命令的函数
void execute_command(const char *command)
{
    // printf("\033[1;36m执行命令: %s\n\033[0m", command);
    char bash_command[1024];
    // 使用 bash -c 来执行包含 source 的命令
    snprintf(bash_command, sizeof(bash_command), "bash -c \"%s\"", command);
    int result = system(bash_command);
    if (result == -1)
    {
        printf("\033[1;31m错误: 命令执行失败\n\033[0m");
    }
    else
    {
        printf("\033[1;32m命令执行完成 (返回码: %d)\n\033[0m", result);
    }
}

int main(int argc, char **argv)
{
    DIR *dir;
    struct dirent *entry;
    struct stat file_stat;
    int file_count = 0;
    int onnx_count = 0;
    int wandb_count = 0;
    int choice;
    char command[512];
    char filepath[512];
    char *onnx_files[256] = {0};
    char *wandb_files[256] = {0};
    printf("\033[1;34m/*************************************************/\n\033[0m");
    printf("\033[1;34m/******************Sim2Sim程序启动*****************/\n\033[0m");
    printf("\033[1;34m/*************************************************/\n\033[0m");
    sleep(1);
    dir = opendir("model");
    if (dir == NULL)
    {
        printf("\033[1;31m错误: 无法打开 model 文件夹\n\033[0m");
        return -1;
    }
    printf("\033[1;34m检查 model 文件夹内容:\n\033[0m");
    while ((entry = readdir(dir)) != NULL)
    {
        snprintf(filepath, sizeof(filepath), "model/%s", entry->d_name);
        if (stat(filepath, &file_stat) == 0)
        {
            if (S_ISREG(file_stat.st_mode))
            {
                // 检查 .onnx 文件
                if (has_suffix(entry->d_name, ".onnx"))
                {
                    onnx_files[onnx_count] = strdup(entry->d_name);
                    onnx_count++;
                }
                // 检查 .wandb 文件
                else if (has_suffix(entry->d_name, ".wandb"))
                {
                    wandb_files[wandb_count] = strdup(entry->d_name);
                    wandb_count++;
                }
                // 其他文件
                else
                {
                    continue;
                }
                file_count++;
            }
            else if (S_ISDIR(file_stat.st_mode))
            {
                // printf("  📁 目录: %s\n", entry->d_name);
                continue;
            }
        }
    }
    closedir(dir);
    if (file_count == 0)
    {
        printf("\033[1;33m警告: model 文件夹内无有效模型文件(.onnx 或 .wandb)。\033[0m\n程序退出\n");
        return -1;
    }
    else
    {
        printf("✓ model 文件夹检查完成，共找到 %d 个模型文件（有 %d 个.onnx，有 %d 个.wandb）。\n", file_count, onnx_count, wandb_count);
    }
    printf("请选择需要加载的模型文件(输入数字):\n");
    for (int i = 0; i < onnx_count; i++)
    {
        printf("  [%d] %s\n", i + 1, onnx_files[i]);
    }
    for (int i = 0; i < wandb_count; i++)
    {
        printf("  [%d] %s\n", onnx_count + i + 1, wandb_files[i]);
    }
    scanf("%d", &choice);
    if (choice < 1 || choice > (onnx_count + wandb_count))
    {
        printf("\033[1;31m错误: 选择无效。\033[0m\n");
        return -1;
    }
    if (choice <= onnx_count)
    {
        printf("✓ 选择加载 Onnx 模型文件: %s\n", onnx_files[choice - 1]);
        sleep(1);
        snprintf(command, sizeof(command), "source /opt/ros/humble/setup.bash && source legged_control2_ws/install/setup.bash &&ros2 launch motion_tracking_controller mujoco.launch.py policy_path:=model/%s", onnx_files[choice - 1]);
    }
    else
    {
        printf("✓ 选择加载 WandB 模型文件: %s\n", wandb_files[choice - onnx_count - 1]);
        sleep(1);
        snprintf(command, sizeof(command), "source /opt/ros/humble/setup.bash &&source legged_control2_ws/install/setup.bash &&launch motion_tracking_controller mujoco.launch.py wandb_path:=model/%s", wandb_files[choice - onnx_count - 1]);
    }
    for (int i = 0; i < onnx_count; i++)
    {
        free(onnx_files[i]);
    }
    for (int i = 0; i < wandb_count; i++)
    {
        free(wandb_files[i]);
    }
    execute_command(command);
    return 0;
}
EOF
cat > ./sim2real.c << 'EOF'
#include <stdio.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <string.h>
#include <stdlib.h>
#include <ifaddrs.h>
#include <net/if.h>

// 检查文件是否有指定后缀
int has_suffix(const char *filename, const char *suffix)
{
    size_t filename_len = strlen(filename);
    size_t suffix_len = strlen(suffix);

    if (filename_len < suffix_len)
    {
        return 0;
    }

    return strcmp(filename + filename_len - suffix_len, suffix) == 0;
}
// 执行终端命令的函数
void execute_command(const char *command)
{
    // printf("\033[1;36m执行命令: %s\n\033[0m", command);
    char bash_command[1024];
    // 使用 bash -c 来执行包含 source 的命令
    snprintf(bash_command, sizeof(bash_command), "bash -c \"%s\"", command);
    int result = system(bash_command);
    if (result == -1)
    {
        printf("\033[1;31m错误: 命令执行失败\n\033[0m");
    }
    else
    {
        printf("\033[1;32m命令执行完成 (返回码: %d)\n\033[0m", result);
    }
}

int list_network_interfaces(char **selected_interface)
{
    int choice;
    char *wangka[64];
    printf("\033[1;34m检测到以下网络接口:\n\033[0m");
    // 使用 ip 命令显示活跃的网络接口
    FILE *fp = popen("ip link show | grep -E '^[0-9]+:' | grep -v 'lo:' | awk -F': ' '{print $2}' | sed 's/@.*//'", "r");
    if (fp == NULL)
    {
        printf("\033[1;31m错误: 无法获取网络接口信息\n\033[0m");
        return -1;
    }

    char interface[64];
    int count = 0;

    while (fgets(interface, sizeof(interface), fp) != NULL)
    {
        // 移除换行符
        interface[strcspn(interface, "\n")] = 0;

        if (strlen(interface) > 0)
        {
            wangka[count] = strdup(interface);
            count++;
            printf("  [%d] %s", count, wangka[count - 1]);
            // 检查接口状态
            char status_cmd[128];
            snprintf(status_cmd, sizeof(status_cmd), "cat /sys/class/net/%s/operstate 2>/dev/null", interface);
            FILE *status_fp = popen(status_cmd, "r");

            if (status_fp != NULL)
            {
                char ip_cmd[512];
                snprintf(ip_cmd, sizeof(ip_cmd), "ip addr show %s | grep 'inet ' | head -1 | awk '{print $2}' | cut -d'/' -f1 2>/dev/null", interface);
                FILE *ip_fp = popen(ip_cmd, "r");

                if (ip_fp != NULL)
                {
                    char ip_addr[64];
                    if (fgets(ip_addr, sizeof(ip_addr), ip_fp) != NULL)
                    {
                        ip_addr[strcspn(ip_addr, "\n")] = 0;
                        if (strlen(ip_addr) > 0)
                        {
                            printf(" \033[1;36m[IP: %s]\033[0m", ip_addr);
                        }
                    }
                    pclose(ip_fp);
                }
                char status[16];
                if (fgets(status, sizeof(status), status_fp) != NULL)
                {
                    status[strcspn(status, "\n")] = 0;
                    if (strcmp(status, "up") == 0)
                    {
                        printf(" 当前状态：\033[1;32m(活跃)\033[0m");
                    }
                    else
                    {
                        printf(" 当前状态：\033[1;33m(未连接)\033[0m");
                    }
                }
                pclose(status_fp);
            }
            printf("\n");
        }
    }
    pclose(fp);
    if (count == 0)
    {
        printf("\033[1;33m警告: 未找到可用的网络接口，程序退出。\033[0m\n");
        return -1;
    }
    printf("请选择通信网卡:\n");
    scanf("%d", &choice);
    while (choice > count || choice < 1)
    {
        printf("\033[1;31m错误: 选择无效，请重新选择。\033[0m\n");
        scanf("%d", &choice);
    }
    *selected_interface = strdup(wangka[choice - 1]);
    printf("✓ 选择的网络接口: %s\n", *selected_interface);
    for (int i = 0; i < count; i++)
    {
        free(wangka[i]);
    }
    return 0;
}

int main(int argc, char **argv)
{
    DIR *dir;
    struct dirent *entry;
    struct stat file_stat;
    int file_count = 0;
    int onnx_count = 0;
    int wandb_count = 0;
    int choice;
    char command[512];
    char filepath[512];
    char *network_select;
    char *onnx_files[256] = {0};
    char *wandb_files[256] = {0};
    printf("\033[1;34m/*************************************************/\n\033[0m");
    printf("\033[1;34m/*****************Sim2Real程序启动*****************/\n\033[0m");
    printf("\033[1;34m/*************************************************/\n\033[0m");
    sleep(1);
    dir = opendir("model");
    if (dir == NULL)
    {
        printf("\033[1;31m错误: 无法打开 model 文件夹\n\033[0m");
        return -1;
    }
    printf("\033[1;34m检查 model 文件夹内容:\n\033[0m");
    while ((entry = readdir(dir)) != NULL)
    {
        snprintf(filepath, sizeof(filepath), "model/%s", entry->d_name);
        if (stat(filepath, &file_stat) == 0)
        {
            if (S_ISREG(file_stat.st_mode))
            {
                // 检查 .onnx 文件
                if (has_suffix(entry->d_name, ".onnx"))
                {
                    onnx_files[onnx_count] = strdup(entry->d_name);
                    onnx_count++;
                }
                // 检查 .wandb 文件
                else if (has_suffix(entry->d_name, ".wandb"))
                {
                    wandb_files[wandb_count] = strdup(entry->d_name);
                    wandb_count++;
                }
                // 其他文件
                else
                {
                    continue;
                }
                file_count++;
            }
            else if (S_ISDIR(file_stat.st_mode))
            {
                // printf("  📁 目录: %s\n", entry->d_name);
                continue;
            }
        }
    }
    closedir(dir);
    if (file_count == 0)
    {
        printf("\033[1;33m警告: model 文件夹内无有效模型文件(.onnx 或 .wandb)。\033[0m\n程序退出\n");
        return -1;
    }
    else
    {
        printf("✓ model 文件夹检查完成，共找到 %d 个模型文件（有 %d 个.onnx，有 %d 个.wandb）。\n", file_count, onnx_count, wandb_count);
    }
    printf("请选择需要加载的模型文件(输入数字):\n");
    for (int i = 0; i < onnx_count; i++)
    {
        printf("  [%d] %s\n", i + 1, onnx_files[i]);
    }
    for (int i = 0; i < wandb_count; i++)
    {
        printf("  [%d] %s\n", onnx_count + i + 1, wandb_files[i]);
    }
    scanf("%d", &choice);
    if (choice < 1 || choice > (onnx_count + wandb_count))
    {
        printf("\033[1;31m错误: 选择无效。\033[0m\n");
        return -1;
    }
    if (list_network_interfaces(&network_select))
    {
        for (int i = 0; i < onnx_count; i++)
        {
            free(onnx_files[i]);
        }
        for (int i = 0; i < wandb_count; i++)
        {
            free(wandb_files[i]);
        }
        return -1;
    }
    if (choice <= onnx_count)
    {
        printf("✓ 选择加载 Onnx 模型文件: %s\n", onnx_files[choice - 1]);
        snprintf(command, sizeof(command), "source /opt/ros/humble/setup.bash && source legged_control2_ws/install/setup.bash &&ros2 launch motion_tracking_controller real.launch.py network_interface:=%s policy_path:=model/%s", network_select, onnx_files[choice - 1]);
    }
    else
    {
        printf("✓ 选择加载 WandB 模型文件: %s\n", wandb_files[choice - onnx_count - 1]);
        snprintf(command, sizeof(command), "source /opt/ros/humble/setup.bash &&source legged_control2_ws/install/setup.bash &&launch motion_tracking_controller real.launch.py network_interface:=%s wandb_path:=model/%s", network_select, wandb_files[choice - onnx_count - 1]);
    }
    for (int i = 0; i < onnx_count; i++)
    {
        free(onnx_files[i]);
    }
    for (int i = 0; i < wandb_count; i++)
    {
        free(wandb_files[i]);
    }
    free(network_select);
    sleep(1);
    execute_command(command);
    return 0;
}
EOF
    gcc -Wall -o sim2sim sim2sim.c
    gcc -Wall -o sim2real sim2real.c
    sudo chmod +x sim2sim
    sudo chmod +x sim2real
    rm -f sim2sim.c sim2real.c
    liucheng_num=12
    echo ${liucheng_num} > .liucheng
fi

if [ ${liucheng_num} -eq 12 ]; then
    rm -f .liucheng
    echo "安装流程已完成"
fi
