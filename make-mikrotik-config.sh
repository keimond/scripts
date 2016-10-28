#!/bin/sh
#
help() {
 case $1 in
  1) echo "~/.settings does not exist, please create it with the appropriate information (see README.md)"
     exit 1;;
  2) cat << EOF
There was an error wih the address, it needs to be in the form of"
w.x.y.z/prefix          Example: 10.45.23.0/24
or
w.x.y.z/subnetmask      Example: 10.45.23.0/255.255.255.0
EOF
echo; echo "\"$2\" is not a valid CIDR notation."
exit 1;;
 esac
} 

test -f ~/.settings && . ~/.settings || help 1

read -p "Site name?: " SITE
read -p "How many ports?: " PORTS
read -p "WAN Address (x.x.x.x/prefix)?: " WINT
ipcalc -s -n ${WINT} >/dev/null 2>&1 || help 2 ${WINT}
read -p "WAN Gateway (x.x.x.x)?: " WGW
ipcalc -s -n ${WGW} >/dev/null 2>&1 || help 2 ${WGW}
read -p "Primary DNS Server ?: " DNS1
ipcalc -s -n ${DNS1} >/dev/null 2>&1 || help 2 ${DNS1}
read -p "How many vmhosts are there ?: " VMHOST
read -p "How many vpnhosts are there ?: " VPNHOST

tz="America/Chicago"
LNET="192.168.88.0/24"
SITE=`echo ${SITE} | tr '[:upper:]' '[:lower:]'`
PORTS=`seq 1 ${PORTS}`

LANNET=`echo ${LNET} | cut -d. -f1-3`
LANIP="${LANNET}.1"
WANIP=`echo ${WINT} | cut -d/ -f1`

while read host num; do
 for x in `seq 1 ${num}`; do
   HOST=(${HOST[@]} $host$x)
 done
done <<< "\
vmhost $VMHOST
vpnhost $VPNHOST"

echo "I'm going to ask for the MAC address of the IPMI interface for each host now."
echo "If you don't have MAC or can't get them, leave the value blank for each machine."
echo "You'll need to have the following packages installed: ipmitool OpenIPMI OpenIPMI-libs"
echo "Once the packages are installed, run the following commands:"
echo
echo "/etc/init.d/ipmi start"
echo "ipmitool lan print|grep 'MAC Address'"
echo

x=1
for srv in ${HOST[@]}; do
  read -p "What is the MAC address for IPMI interface on ${srv}.${SITE} ?: " TMPMAC
  if [ ! `echo $TMPMAC | grep '^([0-9A-F]{2}[:-]){5}([0-9A-F]{2})$'` >/dev/null ]; then
    TMPMAC="00:00:00:00:00:"`printf %02d $x`
  fi
  MAC=(${MAC[@]} $TMPMAC)
  x=$((x+1))
done

echo $
echo;echo;echo;echo;echo;echo


cat << EOF

/interface bridge
add name=LAN
add name=WAN comment="WAN, DON'T DISABLE THIS BRIDGE"
/interface ethernet
EOF

for i in ${PORTS}; do
echo "set [ find default-name=ether$i ] comment=LAN name=ether"`printf %02d $i`
done

cat << EOF
set [ find default-name=sfp1 ] comment="WAN, DON'T DISABLE THIS PORT"
/ip neighbor discovery
set sfp1 comment="WAN, DON'T DISABLE THIS PORT"
set WAN comment="WAN, DON'T DISABLE THIS BRIDGE"
EOF

echo "/ip pool add name=ipmi ranges=${LANNET}.200-$LANNET.254"

cat << EOF
/ip dhcp-server add address-pool=ipmi disabled=no interface=LAN name=ipmi
/interface bridge port 
add bridge=WAN comment="DON'T DISABLE OR REMOVE THIS !!" interface=sfp1
EOF

for i in ${PORTS}; do
echo "add bridge=LAN interface=ether"`printf %02d $i`
done

echo "/ip address"
echo "add address=${LANNET}.1/"`echo ${LNET}|cut -d/ -f2`" comment=gw3.${SITE} interface=LAN network=$LANNET.0"
echo "add address=${WINT} interface=WAN network="`ipcalc -n $WINT|cut -d= -f2`

echo "/ip dhcp-server lease"
n=0; ip=11
for srv in ${HOST[@]}; do
 echo -n "add address=${LANNET}.$ip client-id=1:c:"
 echo -n `echo ${MAC[$n]} | tr '[:lower:]' '[:upper:]'`
 echo -n " comment=ipmi.${srv}.${SITE} mac-address="
 echo -n `echo ${MAC[$n]} | tr '[:upper:]' '[:lower:]'`
 echo " server=ipmi"
 HOSTIP[$n]=${LANNET}.$ip
 n=$((n+1)); ip=$((ip+1))
done

echo "/ip dhcp-server network"
echo "add address=${LNET} dns-server=${DNS1} gateway=${LANNET}.1 netmask=24"

cat <<EOF
/ip dns
set servers=${DNS1}
static add address=${LANNET}.1 name=gw3
/ip firewall address-list
EOF

echo "add address=${LANNET}.1/"`echo ${LNET}|cut -d/ -f2`" comment=\"ACL used for firewall rules for traffic directly to \\\"This device\\\"\" list=ThisDevice"

cat << EOF
add address=216.166.58.0/24 comment="Giganews ACL allowed to SSH/HTTP this device" list=Giganews
add address=216.166.77.0/24 comment="Giganews ACL allowed to SSH/HTTP this device" list=Giganews
add address=207.207.38.0/24 comment=ADC1 list=Giganews
add address=207.207.4.0/25 comment="LP Staff WiFi" list=Giganews
add address=209.99.120.0/24 comment=AlsoADC list=Giganews
/ip firewall filter
add chain=input comment="Allow SSH from ACL Giganews" dst-port=22,443,8291 protocol=tcp src-address-list=Giganews
add chain=input comment="Allow cruncher1.dca1.gn (rancid)" dst-port=22 protocol=tcp src-address=216.166.98.20
add action=drop chain=input comment="Drop Invalid connections" connection-state=invalid
add chain=input comment="Allow Established connections" connection-state=established
add action=drop chain=input comment="Drop everything else"
add action=jump chain=forward comment="ICMP traffic  jumps to icmp chain" jump-target=icmp protocol=icmp
add chain=icmp comment="echo reply" icmp-options=0:0 protocol=icmp
add chain=icmp comment="net unreachable" icmp-options=3:0 protocol=icmp
add chain=icmp comment="host unreachable" icmp-options=3:1 protocol=icmp
add chain=icmp comment="host unreachable fragmentation required" icmp-options=3:4 protocol=icmp
add chain=icmp comment="allow source quench" icmp-options=4:0 protocol=icmp
add chain=icmp comment="allow echo request" icmp-options=8:0 protocol=icmp
add chain=icmp comment="allow time exceed" icmp-options=11:0 protocol=icmp
add chain=icmp comment="allow parameter bad" icmp-options=12:0 protocol=icmp
add action=drop chain=icmp comment="deny all other types"
/ip firewall nat
add action=dst-nat chain=dstnat comment="Port Forward --> localhost SSH" dst-address-list=ThisDevice dst-port=8022 protocol=tcp src-address-list=Giganews to-addresses=${LANIP} to-ports=22
EOF

n=0; c=1
while [ $n -lt $VMHOST ]; do
c1=`printf 8%03d $c`
c2=`printf 6%03d $c`
c3=`printf 4%03d $c`
c4=`printf 2%03d $c`

 echo "add action=dst-nat chain=dstnat comment=\"DNAT ipmi.${HOST[$n]}.${SITE}\" dst-address=${WANIP} dst-port=${c1},${c2},${c3},${c4} protocol=tcp src-address-list=Giganews to-addresses=${HOSTIP[$n]}"
 n=$((n+1)); c=$((c+1))
done

n=0; c=1
c1=`printf 7%03d $c`
c2=`printf 5%03d $c`
c3=`printf 3%03d $c`
c4=`printf 1%03d $c`

while [ $n -lt $VPNHOST ]; do
 echo "add action=dst-nat chain=dstnat comment=\"DNAT ipmi.${HOST[$n]}\" dst-address=${WANIP} dst-port=${c1},${c2},${c3},${c4} protocol=tcp src-address-list=Giganews to-addresses=${HOSTIP[$n]}"
 n=$((n+1)); c=$((c+1))
done

cat << EOF
add action=masquerade chain=srcnat comment="NAT any other traffic to WAN address" out-interface=WAN to-addresses=0.0.0.0
/ip route
add check-gateway=arp comment="Gateway @ Datafoundry" distance=1 gateway=${WGW}
/ip service
set telnet disabled=yes
/ip upnp set allow-disable-external-interface=no
/lcd interface 
set sfp1 interface=sfp1
set ether01 interface=ether01
set ether02 interface=ether02
set ether03 interface=ether03
set ether04 interface=ether04
set ether05 interface=ether05
set ether06 interface=ether06
set ether07 interface=ether07
set ether08 interface=ether08
set ether09 interface=ether09
set ether10 interface=ether10
EOF

echo "/system clock set time-zone-name=${tz}"
echo "/system identity set name=gw3.${SITE}.${domain}"
echo "/system ntp client set enabled=yes primary-ntp=192.168.88.2"

