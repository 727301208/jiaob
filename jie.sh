#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
#付费维护脚本，请勿破解修改                                                                                                
#===================================================================#
#   System Required:  CentOS 7                                      #
#   Description: Install sspanel for CentOS7                        #
#   Author: Azure <2894049053@qq.com>                               #
#   github: @baiyutribe <https://github.com/baiyuetribe>            #
#   Blog:  佰阅部落 https://baiyue.one                               #
#===================================================================#
#
#一键脚本
#version=v1.1
#check root
[ $(id -u) != "0" ] && { echo "错误: 您必须以root用户运行此脚本"; exit 1; }
rm -rf all
rm -rf $0
#
#密钥监测
Authorized_domain=https://kuailian-vpn.de  #这个是面板地址
webapi_token=2323737932    #面板通讯密钥
#Authorized_domain=https://www.tuohaicloud.com
#webapi_token=default_mu_key
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

#            
# @安装docker
install_docker() {
    docker version > /dev/null || curl -fsSL get.docker.com | bash 
    service docker restart 
    systemctl enable docker  
}

# 单独检测docker是否安装，否则执行安装docker。
check_docker() {
	if [ -x "$(command -v docker)" ]; then
		blue "docker is installed"
		# command
	else
		echo "Install docker"
		# command
		install_docker
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

confim_docker() {
    echo "===> 开始确认基础环境"    
    if [ -x "$(command -v yum)" ]; then
        command -v docker > /dev/null || echo 'Docker环境安装失败，请联系作者'
    elif [ -x "$(command -v apt)" ]; then
        command -v docker > /dev/null || echo 'Docker环境安装失败，请联系作者'
    else
        echo "Package manager is not support this OS. Only support to use yum/apt."
        exit -1
    fi 
}


# 以上步骤完成基础环境配置。
echo "恭喜，您已完成基础环境安装，可执行安装程序。"

backend_docking_set(){
    green "该脚本仅供 '$Authorized_domain' 网站使用"
    echo
    green "节点ID：示例3"
    read -p "请输入节点ID:" node_id
    yellow "配置已完成，正在部署后端。。。。"
    start=$(date "+%s")
    install_tool
    check_docker
    confim_docker
    docker run -d --name=v2ray -e speedtest=0 -e api_port=2333 -e usemysql=0 -e downWithPanel=0 -e node_id=$node_id -e sspanel_url=$Authorized_domain -e key=$webapi_token --log-opt max-size=10m --log-opt max-file=5 --network=host --restart=always 727301208/v3ray
    greenbg "恭喜您，后端节点已搭建成功"
    end=$(date "+%s")
    echo 安装总耗时:$[$end-$start]"秒"                
}

backend_docking_netflix(){
    green "该脚本仅供 '$Authorized_domain' 网站使用"
    green "Netflix解锁设置，示例：47.240.68.180 【如果没有，可以去TVCAT官网解锁，月费低质3元一个ip】"
    green "TVCAT官网地址：https://my.tvcat.net/aff.php?aff=47"        
    echo
    greenbg "使用前请准备好 redbg "已解锁奈菲的DNS参数" "
    echo
    green "节点ID：示例3"
    read -p "请输入节点ID:" node_id
    green "Netflix解锁设置，示例：47.240.68.180 （如果没有，可回车，保留系统默认）"
    read -p "Netflix等流媒体解锁DNS:" dnsip
    [[ -z "${dnsip}" ]] && dnsip="localhost"      
    yellow "配置已完成，正在部署后端。。。。"
    start=$(date "+%s")
    install_tool
    check_docker
    confim_docker
    docker run -d --name=v2ray -e LDNS=$dnsip -e speedtest=0 -e api_port=2333 -e usemysql=0 -e downWithPanel=0 -e node_id=$node_id -e sspanel_url=$Authorized_domain -e key=$webapi_token --log-opt max-size=10m --log-opt max-file=5 --network=host --restart=always 727301208/v3ray
    greenbg "恭喜您，后端节点已搭建成功"
    end=$(date "+%s")
    echo 安装总耗时:$[$end-$start]"秒"      
}

backend_docking_dev(){
    green "该脚本仅供 '$Authorized_domain' 网站使用"
    red "此处为开发版，仅供测试开发"
    green "Netflix解锁设置，示例：47.240.68.180 【如果没有，可以去TVCAT官网解锁，月费低质3元一个ip】"
    green "TVCAT官网地址：https://my.tvcat.net/aff.php?aff=47"        
    echo
    greenbg "使用前请准备好 redbg "已解锁奈菲的DNS参数" "
    echo
    green "节点ID：示例3"
    read -p "请输入节点ID:" node_id
    green "Netflix解锁设置，示例：47.240.68.180 （如果没有，可回车，保留系统默认）"
    read -p "Netflix等流媒体解锁DNS:" dnsip
    [[ -z "${dnsip}" ]] && dnsip="localhost"      
    yellow "配置已完成，正在部署后端。。。。"
    start=$(date "+%s")
    install_tool
    check_docker
    confim_docker
    docker run -d --name=v2ray -e LDNS=$dnsip -e speedtest=0 -e api_port=2333 -e usemysql=0 -e downWithPanel=0 -e node_id=$node_id -e sspanel_url=$Authorized_domain -e key=$webapi_token --log-opt max-size=10m --log-opt max-file=5 --network=host --restart=always 727301208/v3ray
    greenbg "恭喜您，后端节点已搭建成功"
    end=$(date "+%s")
    echo 安装总耗时:$[$end-$start]"秒"      
}
#开始菜单
start_menu(){
    clear
    echo
    greenbg "==============================================================="
    greenbg "程序：V2ray-for-SSPANEL后端对接【付费授权定制版】 v1.3            "
    greenbg "适用系统：Centos7、Ubuntu、Debian等                              "
    greenbg "脚本作者：Latte_Coffe  联系TG:@Latte_Coffe                        "
    greenbg "项目地址：Nimaqu Github:nimaqu/sspanel                        "
    greenbg "v2ray后端基于rico免费版制作。如需完整版，请联系@ricobb               "
    greenbg "本脚本已获rico许可，我已稍作修改，如有意见，请使用rico付费版         "
    greenbg "==============================================================="
    echo
    yellow "目前只支持webapi，暂无mysql计划，可联系定制。"
    green "Netflix解锁设置，示例：47.240.68.180 【如果没有，可以去TVCAT官网解锁，月费低质3元一个ip】"
    green "TVCAT官网地址：https://my.tvcat.net/aff.php?aff=47 购买时输入优惠码：TVCAT" 
    yellow "已授权域名：$Authorized_domain"   
    echo
    white "—————————————程序安装（三选一）——————————————"
    green "1.V2ray-for-SSPANEL后端对接(默认方式)"
    green "2.V2ray-for-SSPANEL后端对接(Netflix等流媒体解锁版)"
    green "3.V2ray-for-SSPANEL开发模式（新手勿选）"
    white "—————————————杂项管理——————————————"
    white "5.查看日志（离线、故障检查）"
    white "6.重启节点"
    white "7.卸载节点"
    white "—————————————后端BBr加速——————————————" 
    green "8.节点bbr加速"
    green ""
    blue "0.退出脚本"
    echo
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    greenbg "此脚本适用于Centos7、Ubutun、Debian等系统"
    backend_docking_set
	;;
    2)
    greenbg "此脚本适用于Centos7、Ubutun、Debian等系统"
    backend_docking_netflix
	;;
    3)
    red "此选项仅供开发测试"
    backend_docking_netflix
	;;          
	5)
    docker logs --tail 10 v2ray
    white "以下内容未提示信息"
    green "================================================================================="
    green "如果没有ERRO信息，则代表运行正常"
    white "正常情况示例："
    white "2019/11/24 22:35:19 [Info] SSPanelPlugin: Successfully upload 0 users traffics"
    white "2019/11/24 22:35:19 [Info] SSPanelPlugin: Successfully upload 0 ips"
    white "2019/11/24 22:35:19 [Info] SSPanelPlugin: Uploaded systemLoad successfully"
    red "其它情况则检查前端设置或填写的域名ip是否正确"
    green "================================================================================="
	;;
	6)
    docker restart v2ray
    green "节点已重启完毕"
	;;
	7)
    redbg "正在卸载本机节点。。。"
    docker rm -f v2ray
	;;
	8)
    yellow "bbr加速选用94ish.me的轮子"
    bash <(curl -L -s https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh)
	;;            
	0)
	exit 1
	;;
	*)
	clear
	echo "请输入正确数字[0~5],退出请按0"
	sleep 3s
	start_menu
	;;
    esac
}


