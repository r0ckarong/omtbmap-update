#!/bin/bash
set -e
FILE=mtbgermanylinux.7z
DIRNAME=$(echo $FILE | rev | cut -c9- | rev)
REMOTE_URL=https://ftp.gwdg.de/pub/misc/openstreetmap/openmtbmap/odbl/
REMOTE_FILE=$REMOTE_URL/$FILE
REMOTE_SUM=$REMOTE_URL/md5_hashes/$FILE.txt
SUMFILE="CURR.txt"
SD_LOCATION=/media/maggus/GARMINSD/Garmin/

### Retrieving remote information and compare to local checksum file
echo "[STATUS] Retrieving current checksum..."
http $REMOTE_SUM > $SUMFILE
CHKSUM=$(cat $SUMFILE | grep $FILE | head -n 1 | awk '{print $1 }')
echo "[INFO] Current checksum is: $CHKSUM"

if [ -f "$PWD/$FILE.txt" ]; then
  OLDSUM=$(cat $FILE.txt | grep $FILE | head -n 1 | awk '{print $1}')
  echo "[INFO] Old checksum is: $OLDSUM"
else
  echo "[STATUS] No old checksum found. Overriding."
  export OLDSUM="ABCDEF"
fi

### Remote filesize from HTTP response header
RFS=$(http --print h --json $REMOTE_FILE | cat | grep Length | awk '{print $2}' | tr -d '\r')
RFS=${RFS}

### Local filesize from filesystem
LFS=$(wc -c $PWD/$FILE | awk '{print $1}' | tr -d '\r')
LFS=${LFS}

### Check if we need to download a new file
if [ "$OLDSUM" == "$CHKSUM" ]; then
    echo "[STATUS] No new update. Using existing file."
  else
    #Check if existing download is already the right size
    echo "[INFO] Remote filesize is: $RFS"
    echo "[INFO] Local filesize is: $LFS"

    if [ "$LFS" != "$RFS" ]; then
      #Downloading the new archive
      rm -f $PWD/$FILE
      echo "[STATUS] Local file size mismatch. Downloading file..."
      http -d $REMOTE_FILE > $PWD/$FILE
      if [ -f $PWD/$FILE ]; then
        LFS=$(wc -c $PWD/$FILE | awk '{print $1}' | tr -d '\r')
        LFS=${LFS}
      else
        LFS=0
      fi
    fi
fi

if [ -f $PWD/$FILE ]; then
  echo "[INFO] Local file found..."
  if [ "$LFS" == "$RFS" ]; then
    echo "[STATUS] Checking local file hashsum..."
    VERSUM=$(md5sum $FILE | awk '{print $1}')
    VERSUM=${VERSUM^^}
    echo "[INFO] Local file hashsum is: $VERSUM"
    echo "[INFO] Remote file hashsum is: $CHKSUM"
    if [ "$VERSUM" == "$CHKSUM" ]; then
      echo "[STATUS] Local file up to date..."

      ### Extracting archive and generate new artifacts
      # Removing the old extracted files
      echo "[STATUS] Removing old artifacts..."
      rm -rf $DIRNAME
      rm -f gmapsupp.img gmapsupp.img.md5

      # Extracting new archive to default location "$DIRNAME"
      echo "[STATUS] Unpacking local file..."
      7z x $FILE
      mv $SUMFILE $FILE.txt

      # Switching to data directory and running map generator
      cd $DIRNAME
      echo "[STATUS] Generating map files..."
      mkgmap *.img hikede.TYP --gmapsupp --output-dir=../

      # Generating map file checksum
      cd ../
      echo "[STATUS] Generating md5sum for map file..."
      md5sum gmapsupp.img > gmapsupp.img.md5
    else
      echo "[ERROR] Local file corrupt. Download failed?"
      exit
    fi
  fi
else
  echo "[ERROR] Local file missing. Aborting..."
  exit
fi

### Upload new map file to SD Card
if [ "$1" == "-u" ]; then
  if [ -d $SD_LOCATION ]; then
    echo "[INFO] SD card found..."
  else
    echo "[ERROR] SD card not found. Aborting..."
    exit
  fi

  echo "[STATUS] Removing old map file from SD card..."
  rm -f $SD_LOCATION/gmapsupp.img $SD_LOCATION/gmapsupp.img.md5

  echo "[STATUS] Syncing new map file to SD card..."
  rsync -avP $PWD/gmapsupp.img $PWD/gmapsupp.img.md5 $SD_LOCATION

  echo "[STATUS] Verifying synced map file..."
  md5sum -c $SD_LOCATION/gmapsupp.img.md5
  SD_SUM=$(echo $?)
  #echo "Status was $SD_SUM"

  if [ "$SD_SUM" == "0" ]; then
    echo "[STATUS] Transfer successful. Please remove the SD card."
  else
    echo "[ERROR] Hashsum on SD card does not match after transfer. Aborting..."
    exit
  fi
fi

### Moving updated checksum data to "old", cleaning up unnecessary osm files
echo "[STATUS] Cleaning up..."

# Remove OSM map Files
rm -f osmmap.*

if [ -f $PWD/$SUMFILE ]; then
  rm -f $SUMFILE
fi

if [ -d $PWD/$DIRNAME ]; then
  rm -rf $DIRNAME
fi
