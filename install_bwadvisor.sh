#!/bin/bash

# example invocation:
# scp -i bwpapervirginia.pem install_bwadvisor.sh ubuntu@54.152.84.139:~/
# ssh -i bwpapervirginia.pem ubuntu@54.152.84.139 "sudo INSTALL_DOCKER=Y PARAM_NUMCONTAINERS=2 PARAM_ROLES=nl PARAM_IDENTITY='test/mach1' PARAM_VERSION='v2' PARAM_ARCH=amd64 PARAM_EXTERNALIP=54.152.84.139 ./install_bwadvisor.sh"
if [[ -z "$PARAM_IDENTITY" ]]
then
  echo "ERROR PARAM_IDENTITY required"
  exit 1
fi
if [[ -z "$PARAM_ARCH" ]]
then
  echo "ERROR PARAM_ARCH required (386,amd64,arm-7)"
  exit 1
fi
if [[ -z "$PARAM_EXTERNALIP" ]]
then
  echo "ERROR PARAM_EXTERNALIP required"
  exit 1
fi
if [[ -z "$PARAM_VERSION" ]]
then
  echo "ERROR PARAM_VERSION required (v1)"
  exit 1
fi
if [[ -z "$PARAM_NUMCONTAINERS" ]]
then
  echo "ERROR PARAM_NUMCONTAINERS required (v1)"
  exit 1
fi
if [[ -z "$PARAM_ROLES" ]]
then
  echo "ERROR PARAM_ROLES required"
  exit 1
fi
if [[ -z "$PARAM_NETCLASSES" ]]
then
  echo "ERROR PARAM_NETCLASSES required"
  exit 1
fi
if [[ ${#PARAM_ROLES} != $PARAM_NUMCONTAINERS ]]
then
  echo "ERROR PARAM ROLES IS FUBAR"
  exit 1
fi
if [[ ${#PARAM_NETCLASSES} != $PARAM_NUMCONTAINERS ]]
then
  echo "ERROR PARAM NETCLASSES IS FUBAR"
  exit 1
fi

apt-get update && apt-get install -y ntp wget curl

if [[ "$INSTALL_DOCKER" == "Y" ]]
then

apt-get install -y linux-image-extra-$(uname -r) linux-image-extra-virtual \
apt-transport-https ca-certificates software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get update
apt-get install -y docker-ce
adduser ubuntu docker
fi # end docker

# stop all existing containers
docker rm -f `docker ps -a -q`

systemctl stop bwadvisor.service || true
curl -L https://github.com/immesys/bwadvisor/releases/download/$PARAM_VERSION/bwadvisor-linux-$PARAM_ARCH > /bin/bwadvisor
chmod a+x /bin/bwadvisor

mkdir -p /etc/bwadvisor
echo "BWADVISOR_IDENTITY=$PARAM_IDENTITY" > /etc/bwadvisor/env.ini
echo "BWADVISOR_ARCH=$PARAM_ARCH" >> /etc/bwadvisor/env.ini
echo "BWADVISOR_EXTERNALIP=$PARAM_EXTERNALIP" >> /etc/bwadvisor/env.ini
echo "BWADVISOR_NUMCONTAINERS=$PARAM_NUMCONTAINERS" >> /etc/bwadvisor/env.ini

cat >/etc/systemd/system/bwadvisor.service <<EOF
[Unit]
Description="BWADVISOR"

[Service]
Restart=always
RestartSec=2
EnvironmentFile=/etc/bwadvisor/env.ini
ExecStart=/bin/bwadvisor

[Install]
WantedBy=multi-user.target
EOF

if [[ $PARAM_ARCH == "amd64" ]]
then
  IMAGE=immesys/bw2
else
  IMAGE=immesys/bw2-${PARAM_ARCH}
fi

docker pull $IMAGE

systemctl daemon-reload
systemctl enable bwadvisor

#start containers
for idx in $(seq 0 $(($PARAM_NUMCONTAINERS - 1)))
do
  role=${PARAM_ROLES:$idx:1}
  netclass=${PARAM_NETCLASSES:$idx:1}
  case $netclass in
    "A")
    NET_BW=""
    NET_DELAY=""
    ;;
    "B")
    NET_BW="17200kbit"
    NET_DELAY="5ms"
    ;;
    "C")
    NET_BW="2mbit"
    NET_DELAY="30ms"
    ;;
    "D")
    NET_BW="250kbit"
    NET_DELAY="250ms"
    ;;
  esac

  case $role in
    "n")
    offset=$(($idx*2))
    threads=0
    extOOB=$((28500+$offset));extDPP=$((4500+$offset))
    extSTT=$((7700+$offset));extPRP=$((30400+$offset));extPR5=$((30400+$offset+1))
    cid=$(docker run -d --name=bw2paper_agent_${idx}_${role}_${netclass} --cap-add=NET_ADMIN --cap-add=NET_RAW \
      -e EXTERNALIP=$PARAM_EXTERNALIP -e LISTENPORT=$((30400+$offset)) \
      -p $extPRP:$extPRP -p $extPRP:$extPRP/udp -p $extPR5:$extPR5 -p $extPR5:$extPR5/udp \
      -e MINERTHREADS=$threads -e MINERBENIFICIARY=$mineTo \
      -e MAXPEERS=20 -e MAXLIGHTPEERS=0 \
      -e NET_BW="${NET_BW}" -e NET_DELAY="${NET_DELAY}" \
      $IMAGE)
    printf "CONTAINER_%02d_ID=%s\n" $idx $cid >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_ADDR=%s\n" $idx $(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${cid}) >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_ROLE=%s\n" $idx $role >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_NETCLASS=%s\n" $idx $netclass >> /etc/bwadvisor/env.ini
    ;;
    "s")
    offset=$(($idx*2))
    threads=0
    extOOB=$((28500+$offset));extDPP=$((4500+$offset))
    extSTT=$((7700+$offset));extPRP=$((30400+$offset));extPR5=$((30400+$offset+1))
    cid=$(docker run -d --name=bw2paper_agent_${idx}_${role}_${netclass} --cap-add=NET_ADMIN --cap-add=NET_RAW \
      -e EXTERNALIP=$PARAM_EXTERNALIP -e LISTENPORT=$((30400+$offset)) \
      -p $extPRP:$extPRP -p $extPRP:$extPRP/udp -p $extPR5:$extPR5 -p $extPR5:$extPR5/udp \
      -e MINERTHREADS=$threads -e MINERBENIFICIARY=$mineTo \
      -e MAXPEERS=2 -e MAXLIGHTPEERS=0 \
      -e NET_BW="${NET_BW}" -e NET_DELAY="${NET_DELAY}" \
      $IMAGE)
    printf "CONTAINER_%02d_ID=%s\n" $idx $cid >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_ADDR=%s\n" $idx $(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${cid}) >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_ROLE=%s\n" $idx $role >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_NETCLASS=%s\n" $idx $netclass >> /etc/bwadvisor/env.ini
    ;;
    "m")
    offset=$(($idx*2))
    threads=4
    mineTo=0xf1651ff82a407ab9a210dc94158b728b85909962
    extOOB=$((28500+$offset));extDPP=$((4500+$offset))
    extSTT=$((7700+$offset));extPRP=$((30400+$offset));extPR5=$((30400+$offset+1))
    cid=$(docker run -d --name=bw2paper_agent_${idx}_${role}_${netclass} --cap-add=NET_ADMIN --cap-add=NET_RAW \
      -e EXTERNALIP=$PARAM_EXTERNALIP -e LISTENPORT=$((30400+$offset)) \
      -p $extPRP:$extPRP -p $extPRP:$extPRP/udp -p $extPR5:$extPR5 -p $extPR5:$extPR5/udp \
      -e MINERTHREADS=$threads -e MINERBENIFICIARY=$mineTo \
      -e MAXPEERS=20 -e MAXLIGHTPEERS=0 \
      -e NET_BW="${NET_BW}" -e NET_DELAY="${NET_DELAY}" \
      $IMAGE)
    printf "CONTAINER_%02d_ID=%s\n" $idx $cid >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_ADDR=%s\n" $idx $(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${cid}) >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_ROLE=%s\n" $idx $role >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_NETCLASS=%s\n" $idx $netclass >> /etc/bwadvisor/env.ini
    ;;
    "l")
    offset=$(($idx*2))
    threads=0
    extOOB=$((28500+$offset));extDPP=$((4500+$offset))
    extSTT=$((7700+$offset));extPRP=$((30400+$offset));extPR5=$((30400+$offset+1))
    cid=$(docker run -d --name=bw2paper_agent_${idx}_${role}_${netclass} --cap-add=NET_ADMIN --cap-add=NET_RAW \
      -e EXTERNALIP=$PARAM_EXTERNALIP -e LISTENPORT=$((30400+$offset)) \
      -p $extPRP:$extPRP -p $extPRP:$extPRP/udp -p $extPR5:$extPR5 -p $extPR5:$extPR5/udp \
      -e MINERTHREADS=$threads -e MINERBENIFICIARY=$mineTo \
      -e BW2_MAKECONF_OPTS="--light" \
      -e MAXPEERS=20 -e MAXLIGHTPEERS=10 \
      -e NET_BW="${NET_BW}" -e NET_DELAY="${NET_DELAY}" \
      $IMAGE)
    printf "CONTAINER_%02d_ID=%s\n" $idx $cid >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_ADDR=%s\n" $idx $(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${cid}) >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_ROLE=%s\n" $idx $role >> /etc/bwadvisor/env.ini
    printf "CONTAINER_%02d_NETCLASS=%s\n" $idx $netclass >> /etc/bwadvisor/env.ini
    ;;
  esac
done

sleep 5

systemctl start bwadvisor

echo "SUCCESS"
