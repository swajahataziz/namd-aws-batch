#!/bin/bash

# Create directories for ECS agent
mkdir -p /var/log/ecs /var/lib/ecs/{data,gpu} /etc/ecs

yum install -y jq

# Build array of GPU IDs
DRIVER_VERSION=$(modinfo nvidia --field version)
IFS="\n"
IDS=()
for x in `nvidia-smi -L`; do
  IDS+=$(echo "$x" | cut -f6 -d " " | cut -c 1-40)
done

# Convert GPU IDs to JSON Array
ID_JSON=$(printf '%s\n' "${IDS[@]}" | jq -R . | jq -s -c .)

# Create JSON GPU Object and populate nvidia-gpu-info.json 
echo "\{\"DriverVersion\":\"${DRIVER_VERSION}\",\"GPUIDs\":${ID_JSON}\}" > /var/lib/ecs/gpu/nvidia-gpu-info.json

# Create list of GPU devices
DEVICES=""
for DEVICE_INDEX in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
do
  DEVICE_PATH="/dev/nvidia${DEVICE_INDEX}"
  if [ -e "$DEVICE_PATH" ]; then
    DEVICES="${DEVICES} --device ${DEVICE_PATH}:${DEVICE_PATH} "
  fi
done
DEVICE_MOUNTS=`printf "$DEVICES"`

# Set iptables rules needed to enable Task IAM Roles
echo 'net.ipv4.conf.all.route_localnet = 1' >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
iptables -t nat -A PREROUTING -p tcp -d 169.254.170.2 --dport 80 -j DNAT --to-destination 127.0.0.1:51679
iptables -t nat -A OUTPUT -d 169.254.170.2 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 51679

# Write iptables rules to persist after reboot
iptables-save > /etc/iptables/rules.v4

# Get Docker Hub credentials
pip3 install secretcli
DOCKER_HUB_CREDENTIALS=$(secretcli download docker_hub_readonly -r us-east-1)


# Add ECS Config
cat << EOF > /etc/ecs/ecs.config
ECS_DATADIR=/data
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
ECS_LOGFILE=/log/ecs-agent.log
ECS_AVAILABLE_LOGGING_DRIVERS=["syslog", "json-file", "journald", "awslogs"]
ECS_LOGLEVEL=info
ECS_UPDATES_ENABLED=false
ECS_DISABLE_PRIVILEGED=true
ECS_AWSVPC_BLOCK_IMDS=true
ECS_ENABLE_TASK_ENI=true
ECS_CONTAINER_INSTANCE_PROPAGATE_TAGS_FROM=true
ECS_ENABLE_AWSLOGS_EXECUTIONROLE_OVERRIDE=true
ECS_ENABLE_SPOT_INSTANCE_DRAINING=true
ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=1h
ECS_ENGINE_AUTH_TYPE=docker
ECS_ENGINE_AUTH_DATA={"https://index.docker.io/v1/":$DOCKER_HUB_CREDENTIALS}
ECS_ENABLE_GPU_SUPPORT=true
ECS_NVIDIA_RUNTIME=nvidia
EOF


# Write systemd unit file for ECS Agent
cat << EOF > /etc/systemd/system/docker-container@ecs-agent.service
[Unit]
Description=Docker Container %I
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStartPre=-/usr/bin/docker rm -f %i
ExecStart=/usr/bin/docker run --name %i \
--init \
--restart=on-failure:10 \
--volume=/var/run:/var/run \
--volume=/var/log/ecs/:/log \
--volume=/var/lib/ecs/data:/data \
--volume=/etc/ecs:/etc/ecs \
--volume=/sbin:/host/sbin \
--volume=/lib:/lib \
--volume=/lib64:/lib64 \
--volume=/usr/lib:/usr/lib \
--volume=/usr/lib64:/usr/lib64 \
--volume=/proc:/host/proc \
--volume=/sys/fs/cgroup:/sys/fs/cgroup \
--net=host \
--env-file=/etc/ecs/ecs.config \
--cap-add=sys_admin \
--cap-add=net_admin \
--volume=/var/lib/nvidia-docker/volumes/nvidia_driver/latest:/usr/local/nvidia \
--device /dev/nvidiactl:/dev/nvidiactl \
${DEVICE_MOUNTS} \
--device /dev/nvidia-uvm:/dev/nvidia-uvm \
--volume=/var/lib/ecs/gpu:/var/lib/ecs/gpu \
amazon/amazon-ecs-agent:latest
ExecStop=/usr/bin/docker stop %i

[Install]
WantedBy=default.target
EOF


# Reload daemon files
/bin/systemctl daemon-reload

# Enabling ECS Agent

systemctl start docker-container@ecs-agent.service