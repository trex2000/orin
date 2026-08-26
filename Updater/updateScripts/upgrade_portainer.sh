#!/bin/bash
#portainer
docker stop portainer
docker rm portainer
docker pull portainer/portainer-ce:latest
#agent
docker stop portainer_agent
docker rm portainer_agent
docker pull portainer/agent:latest
docker run -d -p 9001:9001 --name portainer_agent --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes:/var/lib/docker/volumes portainer/agent:latest
docker run -d -p 8100:8000 -p 9443:9443 -p 9100:9000  --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest --trusted-origins barney.ro
