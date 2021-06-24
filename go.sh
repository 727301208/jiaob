#!/bin/bash
#付费维护脚本，请勿破解修改                                                                                             
#===================================================================#
#   System Required:  CentOS 7                                      #
#   Description: Install sspanel for CentOS7                        #
#   Author: Azure <2894049053@qq.com>                               #
#   github: @baiyutribe <https://github.com/baiyuetribe>            #
#   Blog:  佰阅部落 https://baiyue.one                               #
#===================================================================#
#
#  .______        ___       __  ____    ____  __    __   _______      ______   .__   __.  _______ 
#  |   _  \      /   \     |  | \   \  /   / |  |  |  | |   ____|    /  __  \  |  \ |  | |   ____|
#  |  |_)  |    /  ^  \    |  |  \   \/   /  |  |  |  | |  |__      |  |  |  | |   \|  | |  |__   
#  |   _  <    /  /_\  \   |  |   \_    _/   |  |  |  | |   __|     |  |  |  | |  . `  | |   __|  
#  |  |_)  |  /  _____  \  |  |     |  |     |  `--'  | |  |____  __|  `--'  | |  |\   | |  |____ 
#  |______/  /__/     \__\ |__|     |__|      \______/  |_______|(__)\______/  |__| \__| |_______|
#
#一键脚本
#version=v1.1
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#check root
[ $(id -u) != "0" ] && { echo "错误: 您必须以root用户运行此脚本"; exit 1; }
#rm -rf all
#rm -rf $0
#
# 设置字体颜色函数
function blue(){
    echo -e "\033[34m\033[01m $1 \033[0m"
}
function green(){
    echo -e "\033[32m\033[01m $1 \033[0m"
}
function greenbg(){
    echo -e "\033[43;42m\033[01m $1 \033[0m"
}
function red(){
    echo -e "\033[31m\033[01m $1 \033[0m"
}
function redbg(){
    echo -e "\033[37;41m\033[01m $1 \033[0m"
}
function yellow(){
    echo -e "\033[33m\033[01m $1 \033[0m"
}
function white(){
    echo -e "\033[37m\033[01m $1 \033[0m"
}
#单端口
sspanel_port=443

# #webpai模式
# web_url=https://kuailian-vpn.de
# webapi_token=vpn

# #mysql模式
# MYSQL_HOST=140.82.6.22


#mysql模式
MYSQL_HOST=140.82.6.22
mysqldatabase=kuailian_vpn_de
mysqlusername=kuailian_vpn_de
mysqlpassword=dE7TGhkxSGZLcz8D

short_url=`echo $web_url | awk -F '//' '{print $2}'`
#            
# @安装docker
check_gost(){
    ip_addr=`curl -4 ip.sb` &> /dev/null
    if ps -elf | grep 8080?path | grep -v grep
    then
        blue "隧道服务已启动"
    else
        green "正在安装隧道"
        wget -N --no-check-certificate https://github.com/ginuerzh/gost/releases/download/v2.11.0/gost-linux-amd64-2.11.0.gz && gzip -d gost-linux-amd64-2.11.0.gz &> /dev/null
        mv gost-linux-amd64-2.11.0 gost
        chmod +x gost
        nohup ./gost -D -L "ws://:8080?path=/ws&rbuf=4096&wbuf=4096&compression=false" >/dev/null 2>&1 &        
    fi
}

info_gost(){
    if ps -elf | grep 8080?path | grep -v grep
    then
        # 节点服务器修改描述
        echo "1.请在节点服务器，修改描述"
        declare -i quree_port=$nat_port-443
        green "#$quree_port"
        echo "================"
        #ip_addr=`curl -4 ip.sb` &> /dev/null
        echo "2.请在中转服务器上传gost文件，并执行以下命令(如果已上传，则直接运行命令)："
        green "chmod +x gost && nohup ./gost -L=:$nat_port/$ip_addr:40040 -F=ws://$ip_addr:8080/ws >/dev/null 2>&1 &"
    else
        red "ERRO!隧道服务不存在或未启动"
        exit 1
    fi    
}

check_docker_again() {
	if [ -x "$(command -v docker)" ]; then
		blue "Docker check success"
		# command
	else
		redbg "Install docker Faild [Docker环境安装失败]"
        echo "请尝试更换操作系统，脚本支持Centos7、Ubuntu18+、Debian9"
        exit 1
		# command
	fi    
}

# 单独检测docker是否安装，否则执行安装docker。
check_docker() {
	if [ -x "$(command -v docker)" ]; then
		blue "docker is installed"
		# command
	else
		echo "Install docker"
		# command
        docker version > /dev/null || curl -fsSL get.docker.com | bash 
        service docker restart 
        systemctl enable docker
        check_docker_again  
	fi
}

#工具安装
install_tool() {
    echo "===> Start to install tool"    
    if [ -x "$(command -v yum)" ]; then
        command -v curl > /dev/null || yum install -y curl
        systemctl stop firewalld.service
        systemctl disable firewalld.service
    elif [ -x "$(command -v apt)" ]; then
        command -v curl > /dev/null || apt install -y curl
    else
        echo "Package manager is not support this OS. Only support to use yum/apt."
        exit -1
    fi 
}

check_mem(){
    all=`free -m | awk 'NR==2' | awk '{print $2}'`
    used=`free -m | awk 'NR==2' | awk '{print $3}'`
    free=`free -m | awk 'NR==2' | awk '{print $4}'`
}

mysql_install(){
    greenbg "请按提示填写，然后回车"
    read -p "面板节点ID：" node_id
    read -p "NAT中转端口号：" nat_port
    echo "开始安装中..."
    check_docker
    check_gost    
    docker pull baiyuetribe/sspanel:ssr &> /dev/null
    docker rm -f ssrmu &> /dev/null
    #-p $node_port:$sspanel_port/tcp -p $node_port:$sspanel_port/udp
    docker run -d --name=ssrmu -e NODE_ID=$node_id -e API_INTERFACE=glzjinmod -e MYSQL_HOST=$MYSQL_HOST -e MYSQL_USER=$mysqlusername -e MYSQL_DB=$mysqldatabase -e MYSQL_PASS=$mysqlpassword -p 40040:443/tcp -p 40040:443/udp --log-opt max-size=50m --log-opt max-file=3 -e SPEEDTEST=0 --restart=always baiyuetribe/sspanel:ssr
    #docker run -d --name=ssrmu -e NODE_ID=$node_id -e API_INTERFACE=glzjinmod -e MYSQL_HOST=$MYSQL_HOST -e MYSQL_USER=$mysqlusername -e MYSQL_DB=$mysqldatabase -e MYSQL_PASS=$mysqlpassword -p 40040:40040 --log-opt max-size=50m --log-opt max-file=3 -e SPEEDTEST=0 --restart=always baiyuetribe/sspanel:ssr
    #检验是否安装成功    
	if [[ -n "$(docker ps | grep ssrmu)" ]] ; then
		greenbg "节点$node_id启动成功"
        echo "==================="
        echo ""
        info_gost
	else
        redbg "节点$node_id启动失败，请考虑以下原因"
        echo ""
        echo "1.节点端口是否被占用？    解决办法：换个端口"
        echo ""
        echo "2.内存是否不足？ 当前内存状态: | [All：${all}MB] | [Use：${used}MB] | [Free：${free}MB]    解决办法：换高配置机器"
		exit 1
	fi    
}



system_check(){
    echo "Check System"    
    if [ -x "$(command -v yum)" ]; then
        red "中转不推荐使用centos,请使用Ubuntu或Debian"
        exit 3
    elif [ -x "$(command -v apt)" ]; then
        green "system check OK"
    else
        echo "Package manager is not support this OS. Only support to use Ubutun、Debian."
        exit -1
    fi 
}
iptables_install(){
    #排除centos系统
    system_check
    #初始化安装
    if [ ! -f "/root/iptables-pf.sh" ]; then
        wget -O /root/iptables.sh -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/iptables-pf.sh && chmod +x /root/iptables.sh
        greenbg "开始安装iptables"
        echo -e "1" | bash /root/iptables.sh
    fi   
}

check_mem
#开始菜单
start_menu(){
    clear
    green "==============================================================="
    green "程序： SSPANEL后端对接SS\SSR 隧道版【付费定制版】 v2.0               "
    green "操作系统:  支持Centos7、Ubuntu18+、Debian9                        "
    green "==============================================================="
    echo ""
    white "=========程序安装========="
    echo ""
    green "1.安装节点"
    echo ""
    white "=========杂项管理========="
    echo ""
    white "2.查看日志"
    white "3.卸载节点"
    echo ""
    white "=========其他工具========="
    echo ""
    green "6.BBR加速【整机器安装一次即可】"
    green ""
    blue "0.退出脚本"
    
    echo ""
    read -p "请输入数字:" num
 
    case "$num" in
    1)
    mysql_install
	;;
    2)
    docker logs --tail 50 ssrmu
	;;    
	3)
    docker rm -f ssrmu
	;;
	6)
    yellow "bbr加速选用94ish.me的轮子"
    bash <(curl -L -s https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh)
	;;
	0)
	exit 1
	;;
	*)
	clear
	echo "请输入正确数字[0~6],退出请按0"
	sleep 3s
	start_menu
	;;
    esac
}

start_menu
