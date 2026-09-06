sudo mkdir -p /var/lib/piper
sudo chown -R 1000:1000 /var/lib/piper
docker stop wyoming-piper
docker rm wyoming-piper
docker pull  rhasspy/wyoming-piper

docker run -d \
  --name wyoming-piper \
  --restart unless-stopped \
  -p 10200:10200 \
  -v /var/lib/piper:/data \
  rhasspy/wyoming-piper \
  --voice hu_HU-anna-medium
