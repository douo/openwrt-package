#
# Copyright (C) 2018-2020 L-WRT Team
# Copyright (C) 2021 xiaorouji
#
# 由 app.sh 导入，helper_* 的方法表示由 app.sh 调用
#
DNSMASQ_PATH=/etc/dnsmasq.d
# 生成 /var/etc/dnsmasq-passwall.d 下的 dnsmasq 配置文件
# ARG:
#  - ipset 集合名称
#  - dnsmasq 转发的 dns 服务器
#  - 配置文件位置
# PIPE:
#  - 规则文件
gen_dnsmasq_items() {
	local ipsetlist=${1}; shift 1
	local fwd_dns=${1}; shift 1
	local outf=${1}; shift 1

	awk -v ipsetlist="${ipsetlist}" -v fwd_dns="${fwd_dns}" -v outf="${outf}" '
		BEGIN {
			if(outf == "") outf="/dev/stdout";
			split(fwd_dns, dns, ","); setdns=length(dns)>0; setlist=length(ipsetlist)>0;
			if(setdns) for(i in dns) if(length(dns[i])==0) delete dns[i];
			fail=1;
		}
		! /^$/&&!/^#/ {
			fail=0
			if(! (setdns || setlist)) {printf("server=%s\n", $0) >>outf; next;}
			if(setdns) for(i in dns) printf("server=/.%s/%s\n", $0, dns[i]) >>outf;
			if(setlist) printf("ipset=/.%s/%s\n", $0, ipsetlist) >>outf;
		}
		END {fflush(outf); close(outf); exit(fail);}
	'
}


# 强制域名解析到某个 ip
# ARG:
# - ip
# - 配置文件位置
# PIPE:
# - 规则文件
gen_dnsmasq_fake_items() {
	local fwd_dns=${1}; shift 1
	local outf=${1}; shift 1

	awk -v fwd_dns="${fwd_dns}" -v outf="${outf}" '
		BEGIN {
			if(outf == "") outf="/dev/stdout";
			split(fwd_dns, dns, ","); setdns=length(dns)>0;
			if(setdns) for(i in dns) if(length(dns[i])==0) delete dns[i];
			fail=1;
		}
		! /^$/&&!/^#/ {
			fail=0

			if(! setdns) {printf("address=%s\n", $0) >>outf; next;}
			if(setdns) for(i in dns) printf("address=/.%s/%s\n", $0, dns[i]) >>outf;
		}
		END {fflush(outf); close(outf); exit(fail);}
	'
}


helper_prepare() {
	local fwd_dns items item servers msg

        mkdir -p "${TMP_DNSMASQ_PATH}" "${DNSMASQ_PATH}" "/var/dnsmasq.d"
	[ "$(config_t_get global_rules adblock 0)" = "1" ] && {
		ln -s "${RULES_PATH}/adblock.conf" "${TMP_DNSMASQ_PATH}/adblock.conf"
		echolog "  - [$?]广告域名表中域名解析请求直接应答为 '0.0.0.0'"
	}


	if [ "${DNS_MODE}" = "nonuse" ]; then
		echolog "  - 不对域名进行分流解析"
	else
		#屏蔽列表
		sort -u "${RULES_PATH}/block_host" | gen_dnsmasq_fake_items "0.0.0.0" "${TMP_DNSMASQ_PATH}/00-block_host.conf"

		#始终用国内DNS解析节点域名
		fwd_dns="${LOCAL_DNS}"
		servers=$(uci show "${CONFIG}" | grep ".address=" | cut -d "'" -f 2)
		hosts_foreach "servers" host_from_url | grep -v "google.c" | grep '[a-zA-Z]$' | sort -u | gen_dnsmasq_items "vpsiplist,vpsiplist6" "${fwd_dns}" "${TMP_DNSMASQ_PATH}/10-vpsiplist_host.conf"
		echolog "  - [$?]节点列表中的域名(vpsiplist)：${fwd_dns:-默认}"

		#始终用国内DNS解析直连（白名单）列表
		fwd_dns="${LOCAL_DNS}"
		[ -n "$CHINADNS_NG" ] && unset fwd_dns
		sort -u "${RULES_PATH}/direct_host" | gen_dnsmasq_items "whitelist,whitelist6" "${fwd_dns}" "${TMP_DNSMASQ_PATH}/11-direct_host.conf"
		echolog "  - [$?]域名白名单(whitelist)：${fwd_dns:-默认}"

		if [ "$(config_t_get global_subscribe subscribe_proxy 0)" = "0" ]; then
			#如果没有开启通过代理订阅
			fwd_dns="${LOCAL_DNS}"
			for item in $(get_enabled_anonymous_secs "@subscribe_list"); do
				host_from_url "$(config_n_get ${item} url)" | gen_dnsmasq_items "whitelist,whitelist6" "${fwd_dns}" "${TMP_DNSMASQ_PATH}/12-subscribe.conf"
			done
			echolog "  - [$?]节点订阅域名(whitelist)：${fwd_dns:-默认}"
		else
			#如果开启了通过代理订阅
			fwd_dns="${TUN_DNS}"
			[ -n "$CHINADNS_NG" ] && fwd_dns="${china_ng_gfw}"
			for item in $(get_enabled_anonymous_secs "@subscribe_list"); do
				if [ "${DNS_MODE}" = "fake_ip" ]; then
					host_from_url "$(config_n_get ${item} url)" | gen_dnsmasq_fake_items "11.1.1.1" "${TMP_DNSMASQ_PATH}/91-subscribe.conf"
				else
					host_from_url "$(config_n_get ${item} url)" | gen_dnsmasq_items "blacklist,blacklist6" "${fwd_dns}" "${TMP_DNSMASQ_PATH}/91-subscribe.conf"
				fi
			done
			[ "${DNS_MODE}" != "fake_ip" ] && echolog "  - [$?]节点订阅域名(blacklist)：${fwd_dns:-默认}"
		fi

		#始终使用远程DNS解析代理（黑名单）列表
		if [ "${DNS_MODE}" = "fake_ip" ]; then
			sort -u "${RULES_PATH}/proxy_host" | gen_dnsmasq_fake_items "11.1.1.1" "${TMP_DNSMASQ_PATH}/97-proxy_host.conf"
		else
			fwd_dns="${TUN_DNS}"
			[ -n "$CHINADNS_NG" ] && fwd_dns="${china_ng_gfw}"
			[ -n "$CHINADNS_NG" ] && unset fwd_dns
			sort -u "${RULES_PATH}/proxy_host" | gen_dnsmasq_items "blacklist,blacklist6" "${fwd_dns}" "${TMP_DNSMASQ_PATH}/97-proxy_host.conf"
			echolog "  - [$?]代理域名表(blacklist)：${fwd_dns:-默认}"
		fi

		#分流规则
		[ "$(config_n_get $TCP_NODE protocol)" = "_shunt" ] && {
			fwd_dns="${TUN_DNS}"
			local default_node_id=$(config_n_get $TCP_NODE default_node _direct)
			local shunt_ids=$(uci show $CONFIG | grep "=shunt_rules" | awk -F '.' '{print $2}' | awk -F '=' '{print $1}')
			for shunt_id in $shunt_ids; do
				local shunt_node_id=$(config_n_get $TCP_NODE ${shunt_id} nil)
				if [ "$shunt_node_id" = "nil" ] || [ "$shunt_node_id" = "_default" ] || [ "$shunt_node_id" = "_direct" ] || [ "$shunt_node_id" = "_blackhole" ]; then
					continue
				fi
				local shunt_node=$(config_n_get $shunt_node_id address nil)
				[ "$shunt_node" = "nil" ] && continue
				if [ "${DNS_MODE}" = "fake_ip" ]; then
					config_n_get $shunt_id domain_list | grep -v 'regexp:\|geosite:\|ext:' | sed 's/domain:\|full:\|//g' | tr -s "\r\n" "\n" | sort -u | gen_dnsmasq_fake_items "11.1.1.1" "${TMP_DNSMASQ_PATH}/98-shunt_host.conf"
				else
					config_n_get $shunt_id domain_list | grep -v 'regexp:\|geosite:\|ext:' | sed 's/domain:\|full:\|//g' | tr -s "\r\n" "\n" | sort -u | gen_dnsmasq_items "shuntlist,shuntlist6" "${fwd_dns}" "${TMP_DNSMASQ_PATH}/98-shunt_host.conf"
				fi
			done
			[ "${DNS_MODE}" != "fake_ip" ] && echolog "  - [$?]Xray分流规则(shuntlist)：${fwd_dns:-默认}"
		}

		#如果没有使用回国模式
		if [ -z "${returnhome}" ]; then
			[ ! -f "${TMP_PATH}/gfwlist.txt" ] && sed -n 's/^ipset=\/\.\?\([^/]*\).*$/\1/p' "${RULES_PATH}/gfwlist.conf" | sort -u > "${TMP_PATH}/gfwlist.txt"
			if [ "${DNS_MODE}" = "fake_ip" ]; then
				sort -u "${TMP_PATH}/gfwlist.txt" | gen_dnsmasq_fake_items "11.1.1.1" "${TMP_DNSMASQ_PATH}/99-gfwlist.conf"
			else
				fwd_dns="${TUN_DNS}"
				[ -n "$CHINADNS_NG" ] && fwd_dns="${china_ng_gfw}"
				[ -n "$CHINADNS_NG" ] && unset fwd_dns
				sort -u "${TMP_PATH}/gfwlist.txt" | gen_dnsmasq_items "gfwlist,gfwlist6" "${fwd_dns}" "${TMP_DNSMASQ_PATH}/99-gfwlist.conf"
				echolog "  - [$?]防火墙域名表(gfwlist)：${fwd_dns:-默认}"
			fi
			# Not China List 模式
			[ -n "${chnlist}" ] && {
				fwd_dns="${LOCAL_DNS}"
				[ -n "$CHINADNS_NG" ] && unset fwd_dns
				sort -u "${TMP_PATH}/chnlist" | gen_dnsmasq_items "chnroute,chnroute6" "${fwd_dns}" "${TMP_DNSMASQ_PATH}/19-chinalist_host.conf"
				echolog "  - [$?]中国域名表(chnroute)：${fwd_dns:-默认}"
			}
		else
			#回国模式
			if [ "${DNS_MODE}" = "fake_ip" ]; then
				sort -u "${RULES_PATH}/chnlist" | gen_dnsmasq_fake_items "11.1.1.1" "${TMP_DNSMASQ_PATH}/99-chinalist_host.conf"
			else
				fwd_dns="${TUN_DNS}"
				sort -u "${RULES_PATH}/chnlist" | gen_dnsmasq_items "chnroute,chnroute6" "${fwd_dns}" "${TMP_DNSMASQ_PATH}/99-chinalist_host.conf"
				echolog "  - [$?]中国域名表(chnroute)：${fwd_dns:-默认}"
			fi
		fi
	fi

	if [ "${DNS_MODE}" != "nouse" ]; then
		echo "conf-dir=${TMP_DNSMASQ_PATH}" > "/var/dnsmasq.d/dnsmasq-${CONFIG}.conf"

		if [ -z "${CHINADNS_NG}" ] && [ "${IS_DEFAULT_DNS}" = "1" ]; then
			echolog "  - 不强制设置默认DNS"
			return
		else
			echo "${DEFAULT_DNS}" > $TMP_PATH/default_DNS
			msg="ISP"
			servers="${LOCAL_DNS}"
			[ -n "${chnlist}" ] && msg="中国列表以外"
			[ -n "${returnhome}" ] && msg="中国列表"
			[ -n "${global}" ] && msg="全局"

			#默认交给Chinadns-ng处理
			[ -n "$CHINADNS_NG" ] && {
				servers="${china_ng_listen}" && msg="chinadns-ng"
			}

			cat <<-EOF >> "/var/dnsmasq.d/dnsmasq-${CONFIG}.conf"
				$(echo "${servers}" | sed 's/,/\n/g' | gen_dnsmasq_items)
				all-servers
				no-poll
				no-resolv
			EOF
			echolog "  - [$?]以上所列以外及默认(${msg})：${servers}"
		fi
	fi
}


helper_restart(){
	if [ -f "$TMP_PATH/default_DNS" ]; then
		backup_dnsmasq_servers
		sed -i "/list server/d" /etc/config/dhcp >/dev/null 2>&1
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
		restore_dnsmasq_servers
	else
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
	fi
        echolog "重启 dnsmasq 服务[$?]"
}


backup_dnsmasq_servers() {
	DNSMASQ_DNS=$(uci show dhcp | grep "@dnsmasq" | grep ".server=" | awk -F '=' '{print $2}' | sed "s/'//g" | tr ' ' ',')
	if [ -n "${DNSMASQ_DNS}" ]; then
		uci -q set $CONFIG.@global[0].dnsmasq_servers="${DNSMASQ_DNS}"
		uci commit $CONFIG
	fi
}

restore_dnsmasq_servers() {
	OLD_SERVER=$(uci -q get $CONFIG.@global[0].dnsmasq_servers | tr "," " ")
	for server in $OLD_SERVER; do
		uci -q del_list dhcp.@dnsmasq[0].server=$server
		uci add_list dhcp.@dnsmasq[0].server=$server
	done
	uci commit dhcp
	uci -q delete $CONFIG.@global[0].dnsmasq_servers
	uci commit $CONFIG
}

helper_clean() {
        rm -rf $TMP_DNSMASQ_PATH
	rm -rf /var/dnsmasq.d/dnsmasq-$CONFIG.conf
	rm -rf $DNSMASQ_PATH/dnsmasq-$CONFIG.conf
	rm -rf $TMP_DNSMASQ_PATH
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        echolog "重启 dnsmasq 服务[$?]"
}
# 获取系统配置的dns
# upstream1,upstream2...
helper_default_dns(){
    DEFAULT_DNS=$(uci show dhcp | grep "@dnsmasq" | grep "\.server=" | awk -F '=' '{print $2}' | sed "s/'//g" | tr ' ' ',')
    if [ -z "${default}" ]; then
	DEFAULT_DNS=$(echo -n $(sed -n 's/^nameserver[ \t]*\([^ ]*\)$/\1/p' "${RESOLVFILE}" | grep -v "0.0.0.0" | grep -v "127.0.0.1" | grep -v "^::$" | head -2) | tr ' ' ',')
    fi
}

[ $1="helper_clean" ] && helper_clean
