#!/usr/bin/env bash
# begin configuration section.
cmd=run.pl
stage=0
beam=5
decode_mbr=true
min_lmwt=9
max_lmwt=11
word_ins_penalty="0.0"
skip_scoring=false
glm=local/mapping.glm
#end configuration section.

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: local/score_sclite_conf.sh [--cmd (run.pl|queue.pl...)] <data-dir> <lang-dir|graph-dir> <decode-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --stage (0|1|2)                 # start scoring script from part-way through."
  echo "    --decode_mbr (true/false)       # maximum bayes risk decoding (confusion network)."
  echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
  echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
  exit 1;
fi

data=$1
lang=$2 # Note: may be graph directory not lang directory, but has the necessary stuff copied.
dir=$3

model=$dir/../final.mdl # assume model one level up from decoding dir.

#hubscr=$KALDI_ROOT/tools/sctk/bin/hubscr.pl 
#[ ! -f $hubscr ] && echo "Cannot find scoring program at $hubscr" && exit 1;
#hubdir=`dirname $hubscr`

for f in $data/stm $lang/words.txt $lang/phones/word_boundary.int \
     $model $data/segments $data/reco2file_and_channel $dir/lat.1.gz; do
  [ ! -f $f ] && echo "$0: expecting file $f to exist" && exit 1;
done

if [ -f $dir/../frame_subsampling_factor ]; then
  factor=$(cat $dir/../frame_subsampling_factor) || exit 1
  frame_shift_opt="--frame-shift 0.0$factor"
  echo "$0: $dir/../frame_subsampling_factor exists, using $frame_shift_opt"
fi

name=`basename $data`; # e.g. eval2000

mkdir -p $dir/scoring/log

#if [ $stage -le 0 ]; then
  ## the escaping gets a bit crazy here, sorry...
  #for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
    #$cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/get_ctm.LMWT.${wip}.log \
      #mkdir -p $dir/score_LMWT_${wip}/ '&&' \
      #lattice-scale --inv-acoustic-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
      #lattice-add-penalty --word-ins-penalty=$wip ark:- ark:- \| \
      #lattice-prune --beam=$beam ark:- ark:- \| \
      #lattice-to-ctm-conf $frame_shift_opt --decode-mbr=$decode_mbr ark:- - \| \
      #utils/int2sym.pl -f 5 $lang/words.txt  \| \
      #utils/convert_ctm.pl $data/segments $data/reco2file_and_channel \
      #'>' $dir/score_LMWT_${wip}/$name.ctm || exit 1;
  #done
#fi

if [ $stage -le 0 ]; then
  local/get_ctm_unk.sh --cmd "$cmd" \
    $frame_shift_opt \
    --use_segments true \
    --unk-p2g-cmd "python3 local/unk_p2g.py --p2g-cmd 'python3 local/et-g2p-fst/g2p.py --inverse --fst  data/lm/large/char_lm/train.fst --nbest 1'" \
    --unk-word '<unk>' \
    --min-lmwt $min_lmwt \
    --max-lmwt $max_lmwt \
    $data \
    $lang \
    $dir
fi


if [ $stage -le 1 ]; then
# Remove some stuff we don't want to score, from the ctm.
  for x in $dir/score_*/$name.ctm; do
    cp $x ${x}.tmp;
    cat ${x}.tmp | \
      grep -v -E '<unk>' | \
      grep -v -E '<v-noise>' | \
      sort -k1,2 -k3,3n | \
      python3 local/compound-ctm.py \
        "python3 local/compounder.py tmp/compounderlm/G.fst tmp/compounderlm/words.txt" | \
      csrfilt.sh -dh -e  -i ctm $glm  > $x
      #local/ctm_join_fragments.py > $x;
  done
fi

if ! $skip_scoring ; then
  if [ $stage -le 2 ]; then  
    $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score.LMWT.log \
      cat $data/stm \| csrfilt.sh -dh -e  -i stm $glm \> $dir/score_LMWT/stm '&&' \
      sclite -r $dir/score_LMWT/stm stm -h $dir/score_LMWT/${name}.ctm ctm \
        -n "$name.ctm" -o sum rsum prf pra dtl sgml -f 0 -D -F -e utf-8 || exit 1      
    
  fi

  grep Sum $dir/score_*/${name}.ctm.sys | utils/best_wer.sh
fi

exit 0
