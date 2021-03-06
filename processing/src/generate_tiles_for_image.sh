#! /bin/bash
#
# Copyright 2014 Medical Research Council Harwell.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
# @author Gagarine Yaikhom <g.yaikhom@har.mrc.ac.uk>
#

# DESCRIPTION:
#
# This script generates a well organised set of tiles
# from the supplied image file.

export MAGICK_THREAD_LIMIT=1;

# Semantic version
version="0.2";

# Preferred image format
pref_format="jpg";

# Original image file to process.
file_to_process=$1;

# Destination directory for tiles images.
tiles_directory=$2;

# Comma separated tile sizes to generate tiles set for
# E.g., 128,256
tile_sizes=$3

# Comma separated image scales to generate tiles set for
# E.g., 10,25,50,75,100
image_scales=$4



case `uname -s` in
    Darwin)
        sha_cmd="shasum";
        ;;
    *)
        sha_cmd="sha1sum";
        ;;
esac


# The generated tiles has the following filename template:
#
# <total columns>_<total rows>_<row>_<column>.<preferred extension>
#
# where row and column indices start from 0.
function generate_tiles() {
    # Uses ImageMagick to generate tiles
    (cd $1; convert scaled.${extension} -crop $2x$2 -set filename:tile "%[fx:ceil(page.width/$2)]_%[fx:ceil(page.height/$2)]_%[fx:page.y/$2]_%[fx:page.x/$2]" +repage +adjoin "%[filename:tile].$extension"; )

    # Delete the scaled image to reduce space.
    (cd $1; rm -f scaled.${extension}; )
}

# Scales the original image and then generates the tiles
#
# @param $1 Directory that contains the image
# @param $2 Maximum size of a tile in pixels
# @param $3 Scale in percentage
#
# E.g., scale_and_generate_tiles b5eaf5627beae587bc779b68ec8f41b30caa4015 64 80
# will first scale the image by 80% and then generate tiles where each
# tile is smaller or equal to 64x64.
function scale_and_generate_tiles() {
    tiles_dir=$1$2/$3;
    if [[ ! -d "${tiles_dir}" ]]
    then
        #echo "    Directory $tiles_dir for $2x$2 tiles at $3% scale does not exists...";
        mkdir -p ${tiles_dir};
    fi;
    
    # Uses ImageMagick to scale the image
    if [[ ! -z "$3" ]]
    then
        (cd ${tiles_dir}; convert ../../original.${extension} -resize $3% scaled.${extension}; )
    fi;

    generate_tiles ${tiles_dir} $2;
}

# Generates tile set from an original image using supplied tile sizes
# at supplied scales.
#
# @param $1 Directory that contains the image
# @param $2 Comma separate list of maximum sizes of tiles in pixels
# @param $3 Comma separated list of scales in percentage
function generate_tiles_set() {
    checksum_dir=$1;

    if [[ "${extension}" = "dcm" ]]
    then
        #echo "    Converting DICOM to preferred image format...";
        (cd ${checksum_dir}; convert -define dcm:display-range=reset original.${extension} -normalize original.${pref_format}; )
    else
        #echo "    Converting image to preferred image format...";
        (cd ${checksum_dir}; convert original.${extension} original.${pref_format}; )
    fi;

    # Capture return code of last comand
    conversion_status=$?

    # Delete original media file since it is archived in the source directory.
    if [[ "${extension}" != "${pref_format}" ]]
    then
        (cd ${checksum_dir}; rm -f original.${extension}; )
    fi;

    # Check if converion to JPEG was successful; otherwise, stop the tiling.
    if [[ ${conversion_status} -ne 0 ]]
    then
        echo "    Failed to convert media file to JPEG... will abort";
        exit 1;
    fi;

    # we convert all images to preferred image format before processing
    extension="$pref_format";

    # If there were multiple extracted files generated (e.g., TIF), choose
    # the largest file as original image.
    #
    # NOTE: we are assuming TIF files may contain the same image at
    # different zooms; but not different images.
    if [[ `find ${checksum_dir} -maxdepth 1 -iname "*.${pref_format}" -type f | wc -l` -gt 1 ]]
    then
        largest_file=`find ${checksum_dir} -maxdepth 1 -iname "*.${pref_format}" -type f -print0 | xargs -0 du -b | sort -nr | head -n 1 | cut -f 2`;
        if [[ "$largest_file" != "${checksum_dir}original.${pref_format}" ]]
        then
            mv -f ${largest_file} ${checksum_dir}original.${pref_format};
        fi;

        # Delete all of the files except for the original JPEG image to tile
        find ${checksum_dir} ! -iname "original.${pref_format}" -type f -delete;
    fi;

    #echo "    Generating thumbnail...";
    (cd ${checksum_dir}; convert original.${pref_format} -resize 300x thumbnail.${pref_format}; )

    echo "$2" | sed -n 1'p' | tr ',' '\n' |
    while read tile_size;
    do
        #echo "    Generating ${tile_size} x ${tile_size} tiles...";
        echo "$3" | sed -n 1'p' | tr ',' '\n' |
        while read scale;
        do
            #echo "    Generating tiles at scale $scale%...";
            scale_and_generate_tiles ${checksum_dir} ${tile_size} ${scale};
        done;
    done;

    # Delete converted original media file since tiles have been generated.
    (cd ${checksum_dir}; rm -f original.${pref_format}; )
}

if [[ ! $# -eq 4 ]]
then
    echo "Usage:";
    echo "    generate_tiles_for_image.sh <file> <destination> <sizes> <scales>";
    echo "";
    echo " E.g., generate_tiles_for_image.sh example.jpg tiles 256 10,25,50,75,100";
    echo "";
    echo "        file - Original image file to process.";
    echo " destination - Destination directory to store image tiles set.";
    echo "       sizes - Comma separated list of tile sizes (in pixels).";
    echo "      scales - Comma separated list of scales (in percentage).";
    exit 1;
fi;

if [[ ! -f ${file_to_process} ]]
then
    echo "Abort tiling... \"${file_to_process}\" does not exists...";
    exit 1;
fi;

# Ensure target directory ends with '/'
case ${tiles_directory} in
    */)
        ;;
    *) tiles_directory="${tiles_directory}/"
        ;;
esac

if [[ ! -d ${tiles_directory} ]]
then
    mkdir -p ${tiles_directory};
fi;

basename=$(basename "${file_to_process}");
extension="${file_to_process##*.}";
filename=`basename ${basename} .${extension}`;
checksum=`${sha_cmd} ${file_to_process} | cut -d " " -f 1`;

# We could just use the checksum, but the number of directories
# in this flat representation could reach the filesystem limit.
# Furthermore, this could slow down the filesystem. We therefore
# break down the checksum into buckets, where each bucket is
# four characters long, so that the bucket hierarchy depth is ten.
# Hence, at each level, we can have 65536 (16^4) items.
#
# E.g., we get the directory from
#
# b5eaf5627beae587bc779b68ec8f41b30caa4015
#
# as
#
# b5ea/f562/7bea/e587/bc77/9b68/ec8f/41b3/0caa/4015
#
checksum_hierarchy=`echo ${checksum} | sed 's/.\{4\}/&\//g'`
checksum_dir=${tiles_directory}${checksum_hierarchy};
checksum_filepath=${checksum_dir}original.${extension};

if [[ -d "${checksum_dir}" ]]
then
    echo "Tiles directory \"${checksum_dir}\" exists... will delete and redo tiling";
    rm -Rf ${checksum_dir};
fi;

echo "Processing \"${file_to_process}\"...";
mkdir -p ${checksum_dir};
cp -f ${file_to_process} ${checksum_filepath};
generate_tiles_set ${checksum_dir} ${tile_sizes} ${image_scales};
