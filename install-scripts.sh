#!/bin/sh

REPOS="."
SCRIPTS_DIR="/sdcard/Android/data/ru.execbit.aiolauncher/files/"

for repo in $REPOS; do
    adb push $repo/*.lua $SCRIPTS_DIR
done
