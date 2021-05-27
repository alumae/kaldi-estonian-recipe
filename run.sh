#!/bin/bash

# Begin configuration section.
nj=40
decode_nj=10
stage=0

corpusdir=/export2/home/tanel/data/ee-transkriptsioonid

EKSKFK_dir=/export2/home/tanel/data/fonkorpus

declare -A set2trsdir
set2trsdir[broadcast]=`echo ${corpusdir}/{aktuaalne-kaamera,ERR2020,er-uudised,intervjuukorpus,jutusaated,paevakaja,aktuaalne2021}`
set2trsdir[other]=`echo ${corpusdir}/{konverentsid,podcastid,Riigikogu_salvestused,www-trans,seeniorid}`



. ./utils/parse_options.sh

. ./cmd.sh
. ./path.sh

set -e # exit on error

if [ $stage -le 1 ]; then
  for set in "${!set2trsdir[@]}"; do
    mkdir -p data/${set}_unsegmented.all.tmp
    rm -rf data/${set}_unsegmented.all.tmp/wav.scp
    rm -rf data/${set}_unsegmented.all.tmp/reco2trs.scp
    find ${set2trsdir[$set]} -name '*.trs' |  \
    while read f; do \
      fileid=${f#*${corpusdir}/}
      fileid=${fileid%.trs}
      audio=`/bin/ls -1 ${f%.trs}{.wav,.mp3,.mp4,.mpg,.mp2,.ogg,.opus,.m4a}  2> /dev/null | head -1`; \
      if [ -e "$audio" ]; then
        echo "$fileid ffmpeg -nostdin -loglevel panic -i $audio -f sox - | sox -t sox - -c 1 -b 16 -t wav - rate -v 16k |" >> data/${set}_unsegmented.all.tmp/wav.scp
        echo $fileid $f >> data/${set}_unsegmented.all.tmp/reco2trs.scp
      else
        echo "Cannot find audio file for transcription $f" > /dev/stderr
      fi;
    done
    
    # Create dummy utt2spk and spk2utt files so that utils/validate_data_dir.sh won't complain
    awk '{print($1, $1)}' data/${set}_unsegmented.all.tmp/wav.scp > data/${set}_unsegmented.all.tmp/utt2spk
    awk '{print($1, $1)}' data/${set}_unsegmented.all.tmp/wav.scp > data/${set}_unsegmented.all.tmp/spk2utt
    utils/fix_data_dir.sh data/${set}_unsegmented.all.tmp
  done  
fi

if [ $stage -le 10 ]; then
  for set in "${!set2trsdir[@]}"; do
    local/persist_wav_data_dir.sh --cmd "${train_cmd}" --nj $nj \
      data/${set}_unsegmented.all.tmp data/${set}_unsegmented.all data.fast/${set}_unsegmented.all/wavs
    cp data/${set}_unsegmented.all.tmp/reco2trs.scp  data/${set}_unsegmented.all/reco2trs.scp
  done
fi


if [ $stage -le 11 ]; then
  for set in "${!set2trsdir[@]}"; do
      rm -rf data/${set}.all
      mkdir -p data/${set}.all            
      ${CONDA_PREFIX}/bin/python local/trs2data.py data/${set}.all data/${set}_unsegmented.all/reco2trs.scp
      for f in data/${set}_unsegmented.all/{wav.scp,reco2trs.scp}; do
        cp $f data/${set}.all;
      done
      utils/utt2spk_to_spk2utt.pl data/${set}.all/utt2spk > data/${set}.all/spk2utt
      #utils/fix_data_dir.sh data/${set}.all/
      cp data/${set}.all/text data/${set}.all/text.orig 
  done  
fi



if [ $stage -le 12 ]; then
  rm -rf data/ekskfk
  mkdir -p data/ekskfk
  ${CONDA_PREFIX}/bin/python local/fonkorpus_splitter.py data/ekskfk ${EKSKFK_dir}/*/*.TextGrid  
  utils/fix_data_dir.sh data/ekskfk
  cp data/ekskfk/text data/ekskfk/text.orig 
fi



if [ $stage -le 20 ]; then
  utils/combine_data.sh  data/combined.all `for set in "${!set2trsdir[@]}"; do echo data/${set}.all; done` data/ekskfk
  cat `for set in "${!set2trsdir[@]}"; do echo data/${set}.all/reco2trs.scp; done` | sort >  data/combined.all/reco2trs.scp
  
fi



if [ $stage -le 30 ]; then
  cat data/combined.all/segments | grep -v -f <(cat local/devtest_splits/*{devset,testset}.ids) | awk '{print($1)}'  >  data/combined.all/train.utts.txt

  for f in local/devtest_splits/{intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,riigikogu,www-trans,podcasts,aktuaalne2021}.{devset,testset}.ids; do \
    if [ -s $f ]; then
      cat data/combined.all/segments  | grep -f $f | awk '{print($1)}' >  data/combined.all/`basename $f .ids`.utts.txt ;
    fi
  done
  
fi



if [ $stage -le 31 ]; then
  rm -rf data/combined.train data/broadcast.train
  utils/subset_data_dir.sh --utt-list data/combined.all/train.utts.txt  data/combined.all data/combined.train
  utils/subset_data_dir.sh --utt-list data/combined.all/train.utts.txt  data/broadcast.all data/broadcast.train
  
  utils/filter_scp.pl data/broadcast.train/wav.scp data/broadcast.all/reco2trs.scp > data/broadcast.train/reco2trs.scp
    
  for f in data/combined.all/{intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts,aktuaalne2021}.{devset,testset}.utts.txt; do \
    if [ -s $f ]; then
      dir=data/`basename $f .utts.txt`
      rm -rf $dir
      utils/subset_data_dir.sh --utt-list $f  data/combined.all $dir
      utils/filter_scp.pl $dir/wav.scp data/combined.all/reco2trs.scp > $dir/reco2trs.scp
    fi
  done
  
fi  


if [ $stage -le 40 ]; then
  if [ ! -f data/combined.train/text.orig ]; then
    mv data/combined.train/text data/combined.train/text.orig
  fi
  echo "Preprocessing data/combined.train/text"
  cat data/combined.train/text.orig  | ${CONDA_PREFIX}/bin/python local/preprocess_text.py --action process_fragments,split_compounds  --num-skip-fields 1 --target am > data/combined.train/text.punctuated
  cat data/combined.train/text.punctuated | perl -npe 's/(^| )[[:punct:]]($| )/ /g; s/\+[DC]\+//g;'  | LC_ALL="C.UTF-8" grep -v  '[^[:print:][:space:]]' > data/combined.train/text
  utils/fix_data_dir.sh data/combined.train || exit 1;
  rm -rf data/train
  utils/copy_data_dir.sh data/combined.train data/train
  
fi



if [ $stage -le 41 ]; then
  for d in data/{intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts,aktuaalne2021}.{devset,testset}; do \
    if [ -d $d ]; then
      if [ ! -f $d/text.orig ]; then
        mv $d/text $d/text.orig
      fi
      echo "Preprocessing $d/text "
      cat $d/text.orig  | ${CONDA_PREFIX}/bin/python local/preprocess_text.py  --action process_fragments,split_compounds --num-skip-fields 1 --target stm > $d/text.punctuated
      cat $d/text.punctuated | perl -npe 's/(^| )[[:punct:] ]+($| )/ /g; s/\+[DC]\+//g;' > $d/text
    fi
    utils/fix_data_dir.sh $d
  done
  exit;
fi


if [ $stage -le 42 ]; then
  for d in data/{intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts,aktuaalne2021}.{devset,testset}; do \
    echo "Generating $d/stm"
    cat ${d}/wav.scp | awk '{print($1, $1, "A")}' > ${d}/reco2file_and_channel
    local/convert2stm.pl $d \
    | sed 's:<unk>::g' | sed 's:<v-noise>::g' | perl -npe 's/ /<separator> /; s/(^| )[[:punct:] ]+($| )/ /g; s/ +\+D\+ +/-/g; s/ +\+C\+ +//g; s/<v-noise>//g; s/<separator> */ /; s/-[,.!?]//g' \
    | sort -k1,1 -k4,4g \
    > $d/stm
    cp $d/reco2file_and_channel ${d}_hires/reco2file_and_channel
    cp $d/stm ${d}_hires/stm
  done
fi


if [ $stage -le 50 ]; then
  rm -rf data/local/dict
  mkdir -p data/local/dict
  echo "<v-noise> SIL" > data/local/dict/lexicon.txt
  echo "<sil> SIL" >> data/local/dict/lexicon.txt
  echo "<unk> UNK" >> data/local/dict/lexicon.txt  
  cat data/train/text | cut -f 2- -d " " | ngram-count -text - order 1 -write1 - | awk '{print($1)}' | egrep -v "^<" > data/local/dict/vocab
  cat data/local/dict/vocab | local/et-g2p/run.sh |  \
    perl -npe 's/(^\S+)\(\d\)/\1/' | \
    perl -npe 's/\b(\w+) \1\b/\1\1 /g; s/(\s)jj\b/\1j/g; s/(\s)tttt\b/\1tt/g; s/(\s)kkkk\b/\1kk/g; ' | uniq >> data/local/dict/lexicon.txt
    
  echo "SIL"   > data/local/dict/silence_phones.txt
  echo "UNK"   >> data/local/dict/silence_phones.txt
  cat data/local/dict/lexicon.txt | perl -npe 's/\S+\s//; s/ /\n/g' |  egrep -v "^\s*$" | sort | uniq | egrep -v "(UNK)|(SIL)"  > data/local/dict/nonsilence_phones.txt
  
  echo "SIL" > data/local/dict/optional_silence.txt
  touch data/local/dict/extra_questions.txt
  
fi

if [ $stage -le 51 ]; then
  rm -rf data/lang
  utils/prepare_lang.sh \
    --share-silence-phones true \
    data/local/dict '<unk>' data/local/dict/tmp.lang data/lang
  
fi


if [ $stage -le 52 ]; then
  local/train_lms_srilm.sh --oov-symbol "<unk>" --words-file \
    data/lang/words.txt data data/lm
  utils/format_lm.sh data/lang data/lm/lm.gz \
    data/local/dict/lexiconp.txt data/lang
  utils/validate_lang.pl data/lang
fi


if [ $stage -le 60 ]; then
  # Feature extraction
  for x in train {intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts,aktuaalne2021}.{devset,testset}; do      
      steps/make_mfcc.sh --nj $nj --cmd "$train_cmd" data/$x 
      steps/compute_cmvn_stats.sh data/$x
      utils/fix_data_dir.sh data/$x
  done
fi


if [ $stage -le 69 ]; then
  # make a subset for monophone training
  rm -rf data/train_100kshort data/train_30kshort
  utils/subset_data_dir.sh --shortest data/train 100000 data/train_100kshort
  utils/subset_data_dir.sh data/train_100kshort 30000 data/train_30kshort
fi

if [ $stage -le 70 ]; then
  # Starting basic training on MFCC features
  steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
		      data/train_30kshort data/lang exp/mono
fi

if [ $stage -le 71 ]; then
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
		    data/train data/lang exp/mono exp/mono_ali

  steps/train_deltas.sh --cmd "$train_cmd" \
			2500 30000 data/train data/lang exp/mono_ali exp/tri1
fi

if [ $stage -le 72 ]; then
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
		    data/train data/lang exp/tri1 exp/tri1_ali

  steps/train_lda_mllt.sh --cmd "$train_cmd" \
			  4000 50000 data/train data/lang exp/tri1_ali exp/tri2
fi

if [ $stage -le 73 ]; then
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
		    data/train data/lang exp/tri2 exp/tri2_ali

  steps/train_sat.sh --cmd "$train_cmd" \
		     5000 100000 data/train data/lang exp/tri2_ali exp/tri3
fi

if [ $stage -le 74 ]; then
  utils/mkgraph.sh data/lang exp/tri3 exp/tri3/graph
  
  for test in {intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts,aktuaalne2021}.{devset,testset}; do
      steps/decode_fmllr.sh --nj ${decode_nj} --cmd "$decode_cmd --mem 10G" exp/tri3/graph \
        data/$test exp/tri3/decode_$test &
  done  
  wait
fi
