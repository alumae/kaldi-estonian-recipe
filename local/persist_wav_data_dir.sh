#!/bin/bash

stage=0
nj=10
cmd=run.pl

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;


if [ $# -ne 3 ]; then
  echo "Usage: $0 [options] <in-data-dir> <out-dir> <wav-dir>"
  exit 1;  
fi

data=$1
dir=$2
wavdir=$3
# Use absolute directory
mkdir -p $wavdir
wavdir=`readlink -f $wavdir`

utils/copy_data_dir.sh $data $dir  || exit 1;

sdata=$data/split$nj

[[ -d $sdata && $data/wav.scp -ot $sdata ]] || split_data.sh $data $nj || exit 1;

cat $data/wav.scp | awk '{print "'$wavdir'/" $1}' | perl -npe "s#(.*)/.*#\1#" | sort | uniq | xargs mkdir -p

if [ $stage -le 0 ]; then
  $cmd --max-jobs-run 10 --mem 12G JOB=1:$nj $dir/log/persist_wav.JOB.log \
    cat $sdata/JOB/wav.scp \| \
    perl -npe 's#(\S+) (.*[^|])\n\$#\1 cat \2 \|\n#' \| \
    perl -npe 's#ffmpeg#ffmpeg -nostdin#' \| \
    perl -npe 's#(\S+) (.*)#\2 sox -V1 -t wav - '$wavdir'/\1.wav#' \| bash || exit 1;
fi



cat $data/wav.scp | awk '{print $1, "'$wavdir'/" $1 ".wav"}' > $dir/wav.scp  || exit 1;


if [ -f $data/utt2lang ]; then
  cp $data/utt2lang $dir/utt2lang
fi

utils/validate_data_dir.sh --no-feats --no-text --non-print $dir  || exit 1;
