#!/bin/bash -e

if [ "$1" == clean ]; then
    docker build . -t niri-builder --build-arg NEW_NIRI="$(date +%s)"
    shift
else
    docker build . -t niri-builder
fi

docker run --rm --name niri-builder -dp 5020:80 niri-builder

if [ "$1" == install ]; then
    sudo echo Thanks
    curl localhost:5020 | sudo tar -xC /
    echo niri installed
    exit 0
fi

docker cp niri-builder:/package ./artifacts
docker rm -f niri-builder
echo Package built and copied to ./artifacts directory
