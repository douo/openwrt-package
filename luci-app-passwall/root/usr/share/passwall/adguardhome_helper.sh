TMP_AGH_DNS=$TMP_PATH/adguardhome_upstream_dns
TMP_AGH_IPSET=$TMP_PATH/adguardhome_ipset_tmp
TMP_AGH_REWRITES=$TMP_PATH/adguardhome_rewrites_tmp
AGH_YAML=/etc/adguardhome.yaml

gen_items(){
   	local ipsetlist=${1}; shift 1
	local fwd_dns=${1}; shift 1

        awk -v ipsetlist="${ipsetlist}" -v fwd_dns="${fwd_dns}" -v outfs="${TMP_AGH_DNS}" -v outfi="${TMP_AGH_IPSET}" '
	    	BEGIN {
			if(outf == "") outf="/dev/stdout";
			split(fwd_dns, dns, ","); setdns=length(dns)>0; setlist=length(ipsetlist)>0;
			if(setdns) for(i in dns) if(length(dns[i])==0) delete dns[i];
                        if(setlist) printf("    - ") >> outfi
			fail=1;
		}
		! /^$/&&!/^#/ {
			fail=0
			if(! (setdns || setlist)) {printf("%s\n", $0) >>outfs; next;}
                        # AdGuardHome 不支持 [/domain1/]upstream1,upstream2
                        # https://github.com/AdguardTeam/AdGuardHome/issues/2446
			if(setdns) for(i in dns) printf("[/%s/]%s\n", $0, dns[i]) >>outfs;
			if(setlist) printf("%s,", $0) >>outfi;
		}
		END {
                        fflush(outfs);
                        close(outfs);

                        if(setlist) printf("/%s\n", ipsetlist) >> outfi
                        fflush(outfi);
                        close(outfi);

                        exit(fail);
                    }
	'

}

gen_fake_items() {
	local target=${1}; shift 1

        awk -v target="${target}" -v outf="${TMP_AGH_REWRITES}" '
	    	BEGIN {
			if(outf == "") outf="/dev/stdout";
	                fail=1;
		}
		! /^$/&&!/^#/ {
			fail=0
                        printf("    - domain: %s\n      answer: %s", $0, target) >> outf
		}
		END {
                        fflush(outf);
                        close(outf);
                        exit(fail);
                    }
	'

}

helper_prepare(){
	if [ "${DNS_MODE}" != "nouse" ]; then
            echo "$DEFAULT_DNS" | awk -F ',' '{for(i=1;i<NF;i++) print $i}' > $TMP_AGH_DNS
	fi

        if [ "${DNS_MODE}" = "nonuse" ]; then
	    echolog "  - 不对域名进行分流解析"
	else
            #屏蔽列表
	    sort -u "${RULES_PATH}/block_host" | gen_fake_items "0.0.0.0"

	    #始终用国内DNS解析节点域名
	    fwd_dns="${LOCAL_DNS}"
	    servers=$(uci show "${CONFIG}" | grep ".address=" | cut -d "'" -f 2)
	    hosts_foreach "servers" host_from_url | grep -v "google.c" | grep '[a-zA-Z]$' | sort -u | gen_items "vpsiplist,vpsiplist6" "#"
	    echolog "  - [$?]节点列表中的域名(vpsiplist)：${fwd_dns:-默认}"

            #始终用国内DNS解析直连（白名单）列表
	    fwd_dns="${LOCAL_DNS}"
	    [ -n "$CHINADNS_NG" ] && unset fwd_dns
	    sort -u "${RULES_PATH}/direct_host" | gen_items "whitelist,whitelist6" "${fwd_dns}"
	    echolog "  - [$?]域名白名单(whitelist)：${fwd_dns:-默认}"

            #始终使用远程DNS解析代理（黑名单）列表
	    if [ "${DNS_MODE}" = "fake_ip" ]; then
		sort -u "${RULES_PATH}/proxy_host" | gen_fake_items "11.1.1.1"
	    else
		fwd_dns="${TUN_DNS}"
		[ -n "$CHINADNS_NG" ] && fwd_dns="${china_ng_gfw}"
		[ -n "$CHINADNS_NG" ] && unset fwd_dns
		sort -u "${RULES_PATH}/proxy_host" | gen_items "blacklist,blacklist6" "${fwd_dns}"
		echolog "  - [$?]代理域名表(blacklist)：${fwd_dns:-默认}"
	    fi

            #如果开启了通过代理订阅
	    [ "$(config_t_get global_subscribe subscribe_proxy 0)" = "1" ] && {
		fwd_dns="${TUN_DNS}"
		[ -n "$CHINADNS_NG" ] && fwd_dns="${china_ng_gfw}"
		for item in $(get_enabled_anonymous_secs "@subscribe_list"); do
		    if [ "${DNS_MODE}" = "fake_ip" ]; then
			host_from_url "$(config_n_get ${item} url)" | gen_fake_items "11.1.1.1"
		    else
			host_from_url "$(config_n_get ${item} url)" | gen_items "blacklist,blacklist6" "${fwd_dns}"
		    fi
		done
		[ "${DNS_MODE}" != "fake_ip" ] && echolog "  - [$?]节点订阅域名(blacklist)：${fwd_dns:-默认}"
	    }

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
			config_n_get $shunt_id domain_list | grep -v 'regexp:\|geosite:\|ext:' | sed 's/domain:\|full:\|//g' | tr -s "\r\n" "\n" | sort -u | gen_fake_items "11.1.1.1"
		    else
			config_n_get $shunt_id domain_list | grep -v 'regexp:\|geosite:\|ext:' | sed 's/domain:\|full:\|//g' | tr -s "\r\n" "\n" | sort -u | gen_items "shuntlist,shuntlist6" "${fwd_dns}"
		    fi
		done
		[ "${DNS_MODE}" != "fake_ip" ] && echolog "  - [$?]Xray分流规则(shuntlist)：${fwd_dns:-默认}"
	    }


            #如果没有使用回国模式
	    if [ -z "${returnhome}" ]; then
		[ ! -f "${TMP_PATH}/gfwlist.txt" ] && sed -n 's/^ipset=\/\.\?\([^/]*\).*$/\1/p' "${RULES_PATH}/gfwlist.conf" | sort -u > "${TMP_PATH}/gfwlist.txt"
		if [ "${DNS_MODE}" = "fake_ip" ]; then
		    sort -u "${TMP_PATH}/gfwlist.txt" | gen_fake_items "11.1.1.1"
		else
		    fwd_dns="${TUN_DNS}"
		    [ -n "$CHINADNS_NG" ] && fwd_dns="${china_ng_gfw}"
		    [ -n "$CHINADNS_NG" ] && unset fwd_dns
		    sort -u "${TMP_PATH}/gfwlist.txt" | gen_items "gfwlist,gfwlist6" "${fwd_dns}"
		    echolog "  - [$?]防火墙域名表(gfwlist)：${fwd_dns:-默认}"
		fi
		# Not China List 模式
		[ -n "${chnlist}" ] && {
		    fwd_dns="${LOCAL_DNS}"
		    [ -n "$CHINADNS_NG" ] && unset fwd_dns
		    sort -u "${TMP_PATH}/chnlist" | gen_items "chnroute,chnroute6" "${fwd_dns}"
		    echolog "  - [$?]中国域名表(chnroute)：${fwd_dns:-默认}"
		}
	    else
		#回国模式
		if [ "${DNS_MODE}" = "fake_ip" ]; then
		    sort -u "${RULES_PATH}/chnlist" | gen_fake_items "11.1.1.1"
		else
		    fwd_dns="${TUN_DNS}"
		    sort -u "${RULES_PATH}/chnlist" | gen_items "chnroute,chnroute6" "${fwd_dns}"
		    echolog "  - [$?]中国域名表(chnroute)：${fwd_dns:-默认}"
		fi
	    fi
	fi
}


helper_restart(){
    # 首次运行先备份
    [ ! -f "$TMP_PATH/adguardhome.yaml.bk"] && cp $AGH_YAML $TMP_PATH/adguardhome.yaml.bk
    # 插入 upstreamdns
    # 插入 ipset
    # 插入 rewrites
    sed -i -e  "s/\(\s*\)upstream_dns_file.*/\1upstream_dns_file: ${TMP_AGH_DNS//\//\\\/}/"  -e  "s/\(\s*\)ipset.*/\1ipset:/; /ipset.*/r ${TMP_AGH_IPSET}"  -e  "s/\(\s*\)rewrites.*/\1rewrites:/; /rewrites.*/r ${TMP_AGH_REWRITES}" $AGH_YAML

    /etc/init.d/adguardhome restart >/dev/null 2>&1
    echolog "重启 adguardhome 服务[$?]"
}


helper_clean() {
    # 清除 upstreamdns
    # 清除 ipset
    # 清除 rewrites
    sed -i -e  's/\(\s*\)upstream_dns_file.*/\1upstream_dns_file: ""/' -e '/ipset.*/,/filtering_enabled.*/ {s/\(\s*\)ipset.*/\1ipset: []/; /ipset.*/b; /filtering_enabled.*/b; d};' -e '/rewrites.*/,/blocked_services.*/ {s/\(\s*\)rewrites.*/\1rewrites: []/; /rewrites.*/b; /blocked_services.*/b; d};' $AGH_YAML
    rm $TMP_AGH_IPSET
    rm $TMP_AGH_DNS
    rm $TMP_AGH_REWRITES

    /etc/init.d/adguardhome restart >/dev/null 2>&1
    echolog "重启 adguardhome 服务[$?]"
}

# 获取 adguardhome 默认配置的 dns
# stdout: upstream1,upstream2...
helper_default_dns(){
    DEFAULT_DNS=$(sed -n -e '/upstream_dns:/,/upstream_dns_file:/ {/upstream_dns/b; s/\s*-\s//p}'  $AGH_YAML | tr '\n' ',')
}
