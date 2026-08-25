#!/bin/bash
docker stop watchtower
docker rm watchtower
docker pull nickfedor/watchtower
docker run --detach \
    --name watchtower \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --restart unless-stopped \
    nickfedor/watchtower
