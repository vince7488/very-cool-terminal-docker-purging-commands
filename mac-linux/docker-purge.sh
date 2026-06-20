#!/bin/bash

echo "1. Purge all of Docker [1]"
echo "2. One by one [2]"
read -p "Select option: " choice

if [ "$choice" == "1" ]; then
    docker system prune -a --volumes -f
    echo "Complete system wipe done."
elif [ "$choice" == "2" ]; then
    read -p "About to purge all unused containers. Proceed? (y/N) " runCont
    if [[ "$runCont" =~ ^[Yy]$ ]]; then docker container prune -f; fi

    read -p "About to purge all unused images. Proceed? (y/N) " runImg
    if [[ "$runImg" =~ ^[Yy]$ ]]; then docker image prune -a -f; fi

    read -p "About to clear all unused volumes. Proceed? (y/N) " runVol
    if [[ "$runVol" =~ ^[Yy]$ ]]; then docker volume prune -f; fi

    read -p "About to clear all unused networks. Proceed? (y/N) " runNet
    if [[ "$runNet" =~ ^[Yy]$ ]]; then docker network prune -f; fi

    read -p "About to clear all build cache. Proceed? (y/N) " runBld
    if [[ "$runBld" =~ ^[Yy]$ ]]; then docker builder prune -a -f; fi

    echo "All done."
else
    echo "Invalid choice. Exiting."
fi