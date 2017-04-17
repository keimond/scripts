ip=$1
unset binary
for x in 1 2 3 4; do
tmp=`echo $ip|cut -d. -f$x`
btmp=`printf %08d \`echo 'ibase=10;obase=2;'$tmp|bc\``
binary=$binary$btmp
done
echo "binary = "$binary
echo "decimal = "$((2#$binary))
