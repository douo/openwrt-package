gen_items(){
   	local ipsetlist=${1}; shift 1
	local fwd_dns=${1}; shift 1

        awk -v ipsetlist="${ipsetlist}" -v fwd_dns="${fwd_dns}" -v outfs="${TMP_PATH}/agh_server" -v outfi="${TMP_PATH}/agh_ipset" '
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
	local fwd_dns=${1}; shift 1

        awk -v fwd_dns="${fwd_dns}" -v outfs="${TMP_PATH}/agh_server" '
	    	BEGIN {
			if(outf == "") outf="/dev/stdout";
			split(fwd_dns, dns, ","); setdns=length(dns)>0;
			if(setdns) for(i in dns) if(length(dns[i])==0) delete dns[i];
			fail=1;
		}
		! /^$/&&!/^#/ {
			fail=0
			if(! (setdns)) {printf("%s\n", $0) >>outfs; next;}
                        # AdGuardHome 不支持 [/domain1/]upstream1,upstream2
                        # https://github.com/AdguardTeam/AdGuardHome/issues/2446
			if(setdns) for(i in dns) printf("[/%s/]%s\n", $0, dns[i]) >>outfs;
		}
		END {
                        fflush(outfs);
                        close(outfs);

                        exit(fail);
                    }
	'

}
