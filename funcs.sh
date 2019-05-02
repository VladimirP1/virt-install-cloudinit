

gen-cloud-init() {

    if [ ! $# -eq 2 ] ; then
	echo "Usage: $0 <vm name> <out prefix>"
	return 1
    fi

    mkdir -p "$2"
    cd "$2"

    USER_DATA=user-data
    META_DATA=meta-data
    CI_ISO=cidata.iso

cat > $USER_DATA << _EOF_
#cloud-config

# Hostname management
preserve_hostname: False
hostname: $1
fqdn: $1.example.local

runcmd:
  - [ yum, -y, remove, cloud-init ]

output: 
  all: ">> /var/log/cloud-init.log"

ssh_svcname: ssh
ssh_deletekeys: True
ssh_genkeytypes: ['rsa', 'ecdsa']

ssh_authorized_keys:
  - $(cat ~/.ssh/id_rsa.pub)

growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false

_EOF_

    echo "instance-id: $1; local-hostname: $1" > $META_DATA

    echo "Generating ISO for cloud-init..."
    genisoimage -output $CI_ISO -volid cidata -joliet -r $USER_DATA $META_DATA &>> $1.log

}

wait-online-vm() {
    MAC=$(virsh dumpxml $1 | awk -F\' '/mac address/ {print $2}')
    while true
    do
        IP=$(grep -B1 $MAC /var/lib/libvirt/dnsmasq/virbr0.status | head \
             -n 1 | awk '{print $2}' | sed -e s/\"//g -e s/,//)
        if [ "$IP" = "" ]
        then
            sleep 1
        else
            break
        fi
    done

    echo "$(date -R) DONE, IP: $IP, hostname: $1"
}

provision-vm() {

    if [ $# -ne 2 ] ; then
	echo "Usage: $0 <vm name> <config file>"
	return 1
    fi

    . "$2"

    # DIR is set in config
    # IMAGE is set in config
    # CPUS is set n config
    # MEM is set in config

    mkdir -p "$DIR/$1"


    virsh dominfo $1 > /dev/null 2>&1
    if [ "$?" -eq 0 ]; then
	echo "Destroy & Undefine"
	virsh destroy "$1"
	virsh undefine "$1"
    fi

    echo "Gen cloud-init"
    gen-cloud-init "$1" "$DIR/$1"

    DISK="$DIR/$1/image.qcow2"
    CI_ISO="$DIR/$1/cidata.iso"

    echo "cp"
    cp "$IMAGE" "$DISK"

    echo "virt-install"
    virt-install --import --name "$1" --ram "$MEM" --vcpus "$CPUS" --disk \
	"$DISK,format=qcow2,bus=virtio" --disk "$CI_ISO,device=cdrom" --network \
	bridge=virbr0,model=virtio --os-type=linux --os-variant=fedora-unknown --noautoconsole
    
    wait-online-vm "$1"
}

