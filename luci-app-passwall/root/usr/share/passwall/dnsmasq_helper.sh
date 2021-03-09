# 生成 /var/etc/dnsmasq-passwall.d 下的 dnsmasq 配置文件
# ARG:
#  - ipset 集合名称
#  - dnsmasq 转发的 dns 服务器
#  - 配置文件位置
# PIPE:
#  - 规则文件
gen_items() {
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


gen_fake_items() {
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

prepare_helper(){
    	mkdir -p "${TMP_DNSMASQ_PATH}" "${DNSMASQ_PATH}" "/var/dnsmasq.d"
	[ "$(config_t_get global_rules adblock 0)" = "1" ] && {
		ln -s "${RULES_PATH}/adblock.conf" "${TMP_DNSMASQ_PATH}/adblock.conf"
		echolog "  - [$?]广告域名表中域名解析请求直接应答为 '0.0.0.0'"
	}

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

restart_helper(){
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

clean_helper() {
        rm -rf $TMP_DNSMASQ_PATH $TMP_PATH
	rm -rf /var/dnsmasq.d/dnsmasq-$CONFIG.conf
	rm -rf $DNSMASQ_PATH/dnsmasq-$CONFIG.conf
	rm -rf $TMP_DNSMASQ_PATH
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        echolog "重启 dnsmasq 服务[$?]"
}
