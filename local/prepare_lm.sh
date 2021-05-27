#!/bin/bash

# Begin configuration section.
nj=40
stage=0

corpora_dir=/export2/home/tanel/data/et-text-corpora
corpus_texts="etnc19_reference_corpus etnc19_web_2019 etnc19_doaj etnc19_wikipedia_2017 opensubtitles err-subs"
#corpus_texts="opensubtitles err-subs"
#corpus_texts="etnc19_doaj etnc19_wikipedia_2017"
KENLM_BIN=/home/tanel/tools/kenlm/build/bin
vocab_size=200000


KALDI_RNNLM_WEIGHT_MAGNITUDE=0.5
KALDI_RNNLM_MAX_PROPORTION=10


. ./utils/parse_options.sh

. ./cmd.sh
. ./path.sh

set -e # exit on error

if [ $stage -le 1 ]; then
  mkdir -p data/lm/text/source
  for t in ${corpus_texts}; do
    less ${corpora_dir}/${t}.txt.{gz,xz} | fold -s -w 1024 > data/lm/text/source/${t}.txt
  done
fi


if [ $stage -le 2 ]; then
  mkdir -p data/lm/text/preprocessed_punctuated
  for t in ${corpus_texts}; do
    echo "Preprocessing $t"
      local/preprocess_text_parallel.sh --nj ${nj} --cmd "$train_cmd" \
        --actions "filter_text,numbers2text,split_compounds" \
        data/lm/text/source/${t}.txt \
        data/lm/text/preprocessed_punctuated/${t}.txt \
        data/lm/text/preprocessed_punctuated/log/${t}
  done
  
fi


if [ $stage -le 3 ]; then
  mkdir -p data/lm/text/preprocessed_depunctuated
  for t in ${corpus_texts}; do
    echo "Depunctuating $t"
    cat data/lm/text/preprocessed_punctuated/${t}.txt | \
      perl -npe 'use utf8; use open ":std", ":encoding(UTF-8)"; s/ [:;.]/\n/g; s/(^| )[[:punct:]]+( |$)/ /g; s/-,/-/g; s/\+[DC]\+//g;' | \
      grep -v --perl-regexp '^.{0,20}$'  > data/lm/text/preprocessed_depunctuated/${t}.txt
  done
fi

if [ $stage -le 4 ]; then
  cut -f 2- -d " " data/train/text | perl -npe 's/<v-noise>//g;  s/\(\)//g; s/\([^)]+\)//g; s/\S+-//g;' > data/lm/text/preprocessed_depunctuated/train.txt
  for d in data/{intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts}.devset; do \
    cut -f 2- -d " " ${d}/text
  done | perl -npe 's/<v-noise>//g; s/\(\)//g; s/\([^)]+\)//g; s/\S+-//g;' > data/lm/text/preprocessed_depunctuated/dev.txt
fi

if [ $stage -le 5 ]; then
  mkdir -p data/lm/large
  for f in train dev ${corpus_texts}; do 
    ngram-count -text data/lm/text/preprocessed_depunctuated/$f.txt -order 1 -write1 - | grep -v "^<" | gzip -c > data/lm/large/$f.counts1.gz
  done
fi

if [ $stage -le 6 ]; then
  select-vocab -heldout data/lm/large/dev.counts1.gz \
    data/lm/large/train.counts1.gz \
    `for f in ${corpus_texts}; do echo data/lm/large/${f}.counts1.gz; done` > data/lm/large/vocab.weights
fi

if [ $stage -le 7 ]; then
  cat data/lm/large/vocab.weights | LC_ALL=C sort  -k2,2rn | awk '{print($1)}' | \
    egrep -v '^[a-z][[:upper:]]' | \
    egrep -v "^http" | \
    egrep -v "@" | \
    egrep -v "[[:upper:]]{5,}" | \
    egrep -v "^[[:punct:]]*[0-9]"  | \
    egrep -v ".{60,}" | \
    egrep  "^[[:alnum:]_'+-]+$" | \
    egrep  "[[:alnum:]]" |  \
    grep -v --perl-regexp  "[\p{Cyrillic}]+" | \
    egrep "[A-Ya-yÕÄÖÜõäöü]" | \
    head -${vocab_size} > data/lm/large/vocab
fi



if [ $stage -le 8 ]; then
  echo "Computing OOV rate"
  compute-oov-rate data/lm/large/vocab <(zcat data/lm/large/dev.counts1.gz)
  echo "Top 50 OOV words"
  zcat data/lm/large/dev.counts1.gz | LC_COLLATE=C  sort -k1,1  | LC_COLLATE=C  join -v 1 - <(LC_COLLATE=C  sort data/lm/large/vocab) | sort -k2nr | head -50
fi

if [ $stage -le 9 ]; then
  for f in train ${corpus_texts}; do 
      ${KENLM_BIN}/lmplz \
        --text data/lm/text/preprocessed_depunctuated/$f.txt  -o 4 -S 20% --interpolate_unigrams 0 --skip_symbols \
        --arpa data/lm/large/${f}.4g.arpa --prune 0 0 0 1 \
        --limit_vocab_file data/lm/large/vocab
  done
fi

if [ $stage -le 10 ]; then
  for f in train ${corpus_texts}; do 
    ngram -order 4 -unk \
      -ppl data/lm/text/preprocessed_depunctuated/dev.txt \
      -lm data/lm/large/${f}.4g.arpa \
      -debug 2 >  data/lm/large/${f}.4g.ppl
  done
fi

if [ $stage -le 11 ]; then
  compute-best-mix `for f in train ${corpus_texts}; do echo data/lm/large/${f}.4g.ppl; done` >  data/lm/large/4g.best-mix
fi

if [ $stage -le 12 ]; then
  best_mix="`head -1 data/lm/large/4g.best-mix`"
  lms=`for f in train ${corpus_texts}; do echo data/lm/large/${f}.4g.arpa; done`
  echo $best_mix
  echo $lms
  local/make-mix-lm.pl "$lms" "$best_mix"
  ngram -order 4 -unk \
    `local/make-mix-lm.pl "$lms" "$best_mix"` \
    -write-lm data/lm/large/interpolated.4g.arpa \
    -debug 1
fi

if [ $stage -le 13 ]; then

  #ngram -order 4 -unk -lm data/lm/large/interpolated.4g.arpa -prune 1e-6 -write-lm data/lm/large/interpolated.pruned6.4g.arpa
  ngram -order 4 -unk -lm data/lm/large/interpolated.4g.arpa -prune 1e-8 -write-lm data/lm/large/interpolated.pruned8.4g.arpa.gz
  ngram -order 4 -unk -lm data/lm/large/interpolated.4g.arpa -prune 1e-9 -write-lm data/lm/large/interpolated.pruned9.4g.arpa.gz
fi


if [ $stage -le 14 ]; then
  rm -rf data/lm/large/dict
  mkdir -p data/lm/large/dict
  echo "<sil> SIL" >> data/lm/large/dict/lexicon.txt
  echo "<unk> UNK" >> data/lm/large/dict/lexicon.txt  
  cat data/lm/large/vocab | local/et-g2p/run.sh | \
    perl -npe 's/(^\S+)\(\d\)/\1/' | \
    perl -npe 's/\b(\w+) \1\b/\1\1 /g; s/(\s)jj\b/\1j/g; s/(\s)tttt\b/\1tt/g; s/(\s)pppp\b/\1pp/g; s/(\s)kkkk\b/\1kk/g; ' | uniq  >> data/lm/large/dict/lexicon.txt
    
  echo "SIL"   > data/lm/large/dict/silence_phones.txt
  echo "UNK"   >> data/lm/large/dict/silence_phones.txt
  cat data/lm/large/dict/lexicon.txt | perl -npe 's/\S+\s//; s/ /\n/g' |  egrep -v "^\s*$" | sort | uniq | egrep -v "(UNK)|(SIL)"  > data/lm/large/dict/nonsilence_phones.txt
  
  echo "SIL" > data/lm/large/dict/optional_silence.txt
  touch data/lm/large/dict/extra_questions.txt
fi

if [ $stage -le 20 ]; then
  rm -rf data/lang_large
  utils/prepare_lang.sh \
    --share-silence-phones true \
    --phone-symbol-table data/lang/phones.txt \
    data/lm/large/dict '<unk>' data/lm/large/dict/tmp.lang data/lang_large
fi

if [ $stage -le 22 ]; then
  utils/format_lm.sh data/lang_large data/lm/large/interpolated.pruned8.4g.arpa.gz \
    data/lm/large/dict/lexiconp.txt data/lang_large
  utils/validate_lang.pl data/lang_large
fi



if [ $stage -le 24 ]; then
  rm -rf data/lang_larger
  cp -r data/lang_large data/lang_larger
  utils/format_lm.sh data/lang_larger data/lm/large/interpolated.pruned9.4g.arpa.gz \
    data/lm/large/dict/lexiconp.txt data/lang_larger
  utils/validate_lang.pl data/lang_larger
  
fi

if [ $stage -le 26 ]; then

  utils/build_const_arpa_lm.sh \
    data/lm/large/interpolated.pruned9.4g.arpa.gz \
    data/lang_large \
    data/lang_large_rescore_larger
  
fi


# unk model
if [ $stage -le 30 ]; then

  rm -rf data/lm/large/unk_lang_model
	utils/lang/make_unk_lm.sh data/lm/large/dict data/lm/large/unk_lang_model

fi

if [ $stage -le 31 ]; then
  rm -rf data/lang_large_unk
  utils/prepare_lang.sh \
    --unk-fst data/lm/large/unk_lang_model/unk_fst.txt \
    --share-silence-phones true \
    --phone-symbol-table data/lang/phones.txt \
    data/lm/large/dict '<unk>' data/lm/large/dict/tmp.lang data/lang_large_unk
fi

if [ $stage -le 32 ]; then
  rm -rf data/lang_larger_unk
  cp -r data/lang_large_unk data/lang_larger_unk
  utils/format_lm.sh data/lang_larger_unk data/lm/large/interpolated.pruned9.4g.arpa.gz \
    data/lm/large/dict/lexiconp.txt data/lang_larger_unk
  utils/validate_lang.pl data/lang_larger_unk
  
fi


if [ $stage -le 40 ]; then

  mkdir -p data/lm/large/char_lm
  cut -f 1 data/lm/large/dict/lexicon.txt  | grep -v "^<" | sort | uniq > data/lm/large/char_lm/train.txt
  local/make_char_lm.sh data/lm/large/char_lm/train.txt data/lm/large/char_lm/train.fst
fi


# RNNLM

if [ $stage -le 50 ]; then
  #total_num_lines=`for f in train ${corpus_texts}; do 
  #    cat data/lm/text/preprocessed_depunctuated/$f.txt;\
  #  done | egrep -v "^<" | wc -l`
  i=1    
  total_num_lines=10000000;
  mkdir -p exp/rnnlm
  rm -f exp/rnnlm/data_weights.txt
  for f in train ${corpus_texts}; do 
     ngram_weight=`head -1 data/lm/large/4g.best-mix  | perl -npe 's/.*\((.*)\)/\1/' | cut -f $i -d " "`;
     num_lines=`cat data/lm/text/preprocessed_depunctuated/$f.txt | egrep -v "^<" | wc -l`;
     echo "$f has  $num_lines lines, ngram weight is $ngram_weight";
     proportion=`awk 'BEGIN {prop='${total_num_lines}'/'${num_lines}'*'${ngram_weight}'^'$KALDI_RNNLM_WEIGHT_MAGNITUDE'; print(prop < '$KALDI_RNNLM_MAX_PROPORTION' ? prop : '$KALDI_RNNLM_MAX_PROPORTION')}'`;
     echo "RNNLM weigt is $proportion";
     echo $f 1 $proportion >> exp/rnnlm/data_weights.txt
     i=$(($i+1))
  done
fi

if [ $stage -le 51 ]; then
  local/rnnlm/run_tdnn_lstm.sh
fi

# RNNLM backward 

if [ $stage -le 60 ]; then
  mkdir -p data/lm/text/preprocessed_depunctuated_back
  for f in data/lm/text/preprocessed_depunctuated/*.txt; do
    echo "Reversing $f"
    cat $f | reverse-text  > data/lm/text/preprocessed_depunctuated_back/`basename $f`
  done
  
fi

if [ $stage -le 61 ]; then
  local/rnnlm/run_tdnn_lstm.sh --num-jobs-initial 1 --num-jobs-initial 1 \
    --dir exp/rnnlm/rnnlm_lstm_back_1a \
    --text-dir data/lm/text/preprocessed_depunctuated_back
fi
