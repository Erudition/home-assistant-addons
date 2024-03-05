#!/usr/bin/env bash

# apk add ffmpeg
share_folder="/share" # /root/share on host
recording_folder="$share_folder/assist_pipeline"
processed_recording_folder="$share_folder/assist_pipeline/${1:?did not get output folder name}"
processing_folder="$share_folder/assist_pipeline/processing"
max_overall_disk_usage_percent=${2:?did not get max_overall_disk_usage_percent}
max_folder_size_megabytes=${3:?did not get max_folder_size_megabytes}
output_segment_size=${4:?did not get output_segment_size} #seconds

trap "exit" INT # allow quit with Ctrl+C

shopt -s lastpipe # allow while loop to run in current shell so we get access to counters


export FFREPORT=file=$processing_folder/%t.log:level=32 # save ffmpeg output

function getTotalDiskUsage {
    # https://stackoverflow.com/a/45667842
    overall_disk_usage_percent=$(df -Ph $recording_folder | awk 'NR == 2{print $5+0}')
    # https://superuser.com/a/1044209
    recording_folder_size_megabytes=$(du -sxbm $recording_folder | awk '{print $1}')
    recording_folder_size_human_units=$(du -sxbh $recording_folder | awk '{print $1}')
    
    if [ $overall_disk_usage_percent -gt $max_overall_disk_usage_percent ]
    then
	echo "Total disk usage is $overall_disk_usage_percent% which is over the max you set, $max_overall_disk_usage_percent%!"
    else
    	echo "Total disk usage is $overall_disk_usage_percent% which is under the max you set, $max_overall_disk_usage_percent%"
    fi
    
    if [ $recording_folder_size_megabytes -gt $max_folder_size_megabytes ]
    then
	echo "Recording folder size is $recording_folder_size_human_units which is over $max_folder_size_megabytes megabytes!"
    else
    	echo "Recording folder size is $recording_folder_size_human_units which is under the max you set, $max_folder_size_megabytes MB"
    fi
}


function deleteOldestFilesUntilUnderLimit {
    deleted_count=0
    #echo "Deleting oldest .wav and .opus files until overall disk usage is under the limit."
    find $recording_folder -type f \( -iname "*.wav" -o -iname "*.opus" \) -print0 | xargs -0 ls -1rt | while read -r file; do
        if [ $(df -Ph $recording_folder | awk 'NR == 2{print $5+0}') -ge $max_overall_disk_usage_percent ] || [ $(du -sxbm $recording_folder | awk '{print $1}') -ge $max_folder_size_megabytes ]
        then
            rm -f "$file"
            ((deleted_count++))
        else
            echo "Deleted $deleted_count oldest recordings. Folder is small enough to continue."
            break
        fi
    done
}


# TODO: segment timestamps currently assume no silence removed
function recordingConvertTrimCompress {
    file_basename=$(basename "$1" .wav)
    file_date=$(date -r "$1" '+%s') # unix time
    wav_size_megabytes=$(du -sxbm "$1" | awk '{print $1}')
    wav_size_kilobytes=$(du -sxb "$1" | awk '{print $1}')
    echo
    echo "Processing $wav_size_megabytes MB recording: $1"
    ffprobe "$1" 2>&1 | grep "Duration"

    /usr/bin/time -f "Time Taken: %E, CPU: %P (out of $(nproc)00%)" \
    ffmpeg -loglevel error -hide_banner -y -i "$1" -nostdin -c:a libopus -ac 1 -b:a 24K -af silenceremove=timestamp=copy:stop_duration=1:window=0:detection=peak:stop_mode=all:start_mode=all:stop_periods=-1:stop_threshold=-30dB -f segment -segment_time $output_segment_size -reset_timestamps 1 "$processing_folder/%d.opus"
    
    cd $processing_folder
    all_segments_size_megabytes=$(du -sxbm "$processing_folder" | awk '{print $1}')
    all_segments_size_kilobytes=$(du -sxb "$processing_folder" | awk '{print $1}')
    saved_megabytes=$(( wav_size_megabytes - all_segments_size_megabytes))
    saved_kilobytes=$(( wav_size_kilobytes - all_segments_size_kilobytes))
    # using bc allows floating point division and prevents div by zero crash
    saved_percent=$( echo "scale=4; 100 - ($saved_kilobytes / $wav_size_kilobytes * 100)" | bc)
    echo "Done. New Total: $all_segments_size_megabytes MB, Saved: $saved_megabytes MB ($saved_percent% smaller)"
    for processed_filename in *.opus
        do
            segment_number=$(basename "$processed_filename" .opus)
            #echo "Moving finished $processed_filename (segment #$segment_number) with $file_date"
            segment_timestamp=$(( (output_segment_size * segment_number) + file_date))
            new_timestamp=$(date -d@"$segment_timestamp" '+%F %T')
            date_only=$(date -d@"$segment_timestamp" '+%Y-%m-%d')
            #echo "Segment #$segment_number has date $new_timestamp"
            mkdir -p "$processed_recording_folder/$date_only"
            mv $processed_filename "$processed_recording_folder/$date_only/$new_timestamp-$file_basename.opus"
    done
    rm -f "$1"
    #echo "Compressed, trimmed silence, and split into the the recordings folder, and deleted original: $1"
}

function convertAllWaveFiles {
    # https://stackoverflow.com/a/26349346
    find $recording_folder -name '*.wav' -print0 | while IFS= read -r -d '' file; do recordingConvertTrimCompress "$file"; done
}




# START ---------------------------------


mkdir -p $processed_recording_folder
mkdir -p $processing_folder
rm -rf $processing_folder/*

getTotalDiskUsage
before_recording_folder_size_human_units=$recording_folder_size_human_units

deleteOldestFilesUntilUnderLimit
convertAllWaveFiles


# FINISH --------------------------------

#getTotalDiskUsage
echo
echo "Tidy Complete. Recording folder went from " $before_recording_folder_size_human_units " to " $recording_folder_size_human_units

# Delete all empty folders
find $recording_folder -type d -empty -delete

# Delete processing folder to show we're not running anymore
rm -rf $processing_folder
