#!/usr/bin/env bash



# Begin configuration section.

language=amharic

embedding_dim=1024
lstm_rpd=256
lstm_nrpd=256
stage=0
train_stage=-10
epochs=10
num_jobs_initial=3
num_jobs_final=5

dir=exp/rnnlm/rnnlm_lstm_1a
text_dir=data/lm/text/preprocessed_depunctuated
lang=data/lang_large_unk
#tree_dir=exp/chain/tree_sp

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh


mkdir -p $dir/config
set -e


if [ $stage -le 1 ]; then
  cp $lang/words.txt $dir/config/
  n=`cat $dir/config/words.txt | wc -l`
  echo "<brk> $n" >> $dir/config/words.txt

  # words that are not present in words.txt but are in the training or dev data, will be
  # mapped to <SPOKEN_NOISE> during training.
  echo "<unk>" >$dir/config/oov.txt
  cp exp/rnnlm/data_weights.txt  $dir/config/data_weights.txt

  rnnlm/get_unigram_probs.py --vocab-file=$dir/config/words.txt \
                             --unk-word="<unk>" \
                             --data-weights-file=exp/rnnlm/rnnlm_lstm_1a/config/data_weights.txt \
                             $text_dir | awk 'NF==2' >$dir/config/unigram_probs.txt

  # choose features
  rnnlm/choose_features.py --unigram-probs=$dir/config/unigram_probs.txt \
                           --use-constant-feature=true \
                           --special-words='<s>,</s>,<brk>,<unk>,<sil>' \
                           $dir/config/words.txt > $dir/config/features.txt

  cat >$dir/config/xconfig <<EOF
input dim=$embedding_dim name=input
relu-renorm-layer name=tdnn1 dim=$embedding_dim input=Append(0, IfDefined(-1))
fast-lstmp-layer name=lstm1 cell-dim=$embedding_dim recurrent-projection-dim=$lstm_rpd non-recurrent-projection-dim=$lstm_nrpd
relu-renorm-layer name=tdnn2 dim=$embedding_dim input=Append(0, IfDefined(-2))
fast-lstmp-layer name=lstm2 cell-dim=$embedding_dim recurrent-projection-dim=$lstm_rpd non-recurrent-projection-dim=$lstm_nrpd
relu-renorm-layer name=tdnn3 dim=$embedding_dim input=Append(0, IfDefined(-1))
output-layer name=output include-log-softmax=false dim=$embedding_dim
EOF
  rnnlm/validate_config_dir.sh $text_dir $dir/config
fi

if [ $stage -le 2 ]; then
  rnnlm/prepare_rnnlm_dir.sh $text_dir $dir/config $dir
fi

if [ $stage -le 3 ]; then
  rnnlm/train_rnnlm.sh --num-jobs-initial ${num_jobs_initial} --num-jobs-final ${num_jobs_final} --num-egs-threads 2  \
                  --stage $train_stage --num-epochs $epochs --cmd "$train_cmd" $dir
fi

