#!/bin/bash



set -e

# configs for 'chain'
stage=12
train_stage=-10
get_egs_stage=-10
dir=exp/chain/`basename $0 | perl -npe 's/^run_(.*)\.sh/\1/'`
decode_iter=
nj=40
decode_nj=3


online_cmvn=true
ivector_dir=

# training options
num_epochs=4
initial_effective_lrate=0.00025
final_effective_lrate=0.000025
leftmost_questions_truncate=-1
max_param_change=2.0
final_layer_normalize_target=0.5
num_jobs_initial=3
num_jobs_final=5
minibatch_size=64
frames_per_eg=150,110,100
remove_egs=false
common_egs_dir=
xent_regularize=0.1
dropout_schedule='0,0@0.20,0.5@0.50,0'

test_online_decoding=false  # if true, it will run the last decoding stage.

run_rnnlm_rescore=true

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

echo "Experiment dir is $dir"

ali_dir=exp/tri3_ali_train_sp
treedir=exp/chain/tri3_tree
lang=data/lang_chain_2y
lat_dir=exp/tri3_ali_train_sp_aug_lats/
gmm_dir=exp/tri3
lores_train_data_dir=data/train_sp


## if we are using the speed-perturbed data we need to generate
## alignments for it.
#local/nnet3/multi_condition/run_ivector_common-x.sh --stage $stage \
  #--num-data-reps $num_data_reps|| exit 1;


if [ $stage -le 12 ]; then
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  rm -rf $lang
  cp -r data/lang $lang
  silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
  nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
  # Use our special topology... note that later on may have to tune this
  # topology.
  steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
fi

if [ $stage -le 13 ]; then
  # Build a tree using our new topology.
  steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
      --leftmost-questions-truncate $leftmost_questions_truncate \
      --context-opts "--context-width=2 --central-position=1" \
      --cmd "$train_cmd" 8000 data/train_sp $lang $ali_dir $treedir
fi


# if [ $stage -le 14 ]; then
#   # Note: it might appear that this $lang directory is mismatched, and it is as
#   # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
#   # the lang directory.
#   utils/lang/make_unk_lm.sh data/local/dict exp/unk_lang_model || exit 1;
#   utils/prepare_lang.sh --unk-fst exp/unk_lang_model/unk_fst.txt  data/local/dict '<unk>' data/local/lang data/lang_unk  || exit 1;

# fi

# if [ $stage -le 15 ]; then
#   cp data/testlm_unk/G.fst  data/lang_unk 
#   utils/mkgraph.sh --self-loop-scale 1.0 data/lang_unk $dir $dir/graph_unk

# fi


#clean_lat_dir=exp/tri3b_lats_train_sp  

#if [ $stage -le 16 ]; then

  ## Get the alignments as lattices (gives the CTC training more freedom).
  ## use the same num-jobs as the alignments
  #steps/align_fmllr_lats.sh --nj $nj --cmd "$train_cmd" data/train_sp \
    #data/lang exp/tri3b $clean_lat_dir
  #rm -f $clean_lat_dir/fsts.*.gz # save space
#fi

#if [ $stage -le 17 ]; then
  ##Create the lattices for the reverberated data
  ## We use the lattices/alignments from the clean data for the reverberated data.
  #mkdir -p $lat_dir/temp/
  #lattice-copy "ark:gunzip -c $clean_lat_dir/lat.*.gz |" ark,scp:$lat_dir/temp/lats.ark,$lat_dir/temp/lats.scp

  ## copy the lattices for the reverberated data
  #rm -f $lat_dir/temp/combined_lats.scp
  #touch $lat_dir/temp/combined_lats.scp
  ## Here prefix "rev0_" represents the clean set, "rev1_" represents the reverberated set
  #for i in `seq 0 $num_data_reps`; do
    #cat $lat_dir/temp/lats.scp | sed -e "s/^/rev${i}_/" >> $lat_dir/temp/combined_lats.scp
  #done
  #for i in `seq 1 $num_data_reps`; do
    #cat $lat_dir/temp/lats.scp | sed -e "s/^/extr_rev${i}_/" >> $lat_dir/temp/combined_lats.scp
  #done

  #sort -u $lat_dir/temp/combined_lats.scp > $lat_dir/temp/combined_lats_sorted.scp

  ##lattice-copy scp:$lat_dir/temp/combined_lats_sorted.scp ark,scp:"|gzip -c >$lat_dir/lat.gz",$lat_dir/lat.scp || exit 1;
  #echo $nj > $lat_dir/num_jobs
  
  #sdata=data/train_sp_combined_rvb${num_data_reps}_hires/split$nj
  #utils/split_data.sh data/train_sp_combined_rvb${num_data_reps}_hires $nj
  #echo "Splitting the multi-condition lattices to $nj files"
  #$train_cmd JOB=1:$nj $lat_dir/log/split_lattices.JOB.LOG \
    #utils/filter_scp.pl $sdata/JOB/utt2spk $lat_dir/temp/combined_lats_sorted.scp \| \
    #lattice-copy scp:- ark:"|gzip -c >$lat_dir/lat.JOB.gz"
  
    
  
  ## copy other files from original lattice dir
  #for f in cmvn_opts final.mdl splice_opts tree phones.txt; do
    #cp $clean_lat_dir/$f $lat_dir/$f
  #done
#fi






if [ $stage -le 18 ]; then
  echo "$0: creating neural net configs using the xconfig parser";

  num_targets=$(tree-info $treedir/tree |grep num-pdfs|awk '{print $2}')
  learning_rate_factor=$(echo "print (0.5/$xent_regularize)" | python)

  cnn_opts="l2-regularize=0.01"
  ivector_affine_opts="l2-regularize=0.01"
  tdnnf_first_opts="l2-regularize=0.01 dropout-proportion=0.0 bypass-scale=0.0"
  tdnnf_opts="l2-regularize=0.01 dropout-proportion=0.0 bypass-scale=0.66"
  linear_opts="l2-regularize=0.01 orthonormal-constraint=-1.0"
  prefinal_opts="l2-regularize=0.01"
  output_opts="l2-regularize=0.002"

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=100 name=ivector
  input dim=40 name=input
  # this takes the MFCCs and generates filterbank coefficients.  The MFCCs
  # are more compressible so we prefer to dump the MFCCs to disk rather
  # than filterbanks.
  idct-layer name=idct input=input dim=40 cepstral-lifter=22 affine-transform-file=$dir/configs/idct.mat
  linear-component name=ivector-linear $ivector_affine_opts dim=200 input=ReplaceIndex(ivector, t, 0)
  batchnorm-component name=ivector-batchnorm target-rms=0.025
  batchnorm-component name=idct-batchnorm input=idct
  combine-feature-maps-layer name=combine_inputs input=Append(idct-batchnorm, ivector-batchnorm) num-filters1=1 num-filters2=5 height=40
  conv-relu-batchnorm-layer name=cnn1 $cnn_opts height-in=40 height-out=40 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=64 
  conv-relu-batchnorm-layer name=cnn2 $cnn_opts height-in=40 height-out=40 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=64
  conv-relu-batchnorm-layer name=cnn3 $cnn_opts height-in=40 height-out=20 height-subsample-out=2 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=128
  conv-relu-batchnorm-layer name=cnn4 $cnn_opts height-in=20 height-out=20 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=128
  conv-relu-batchnorm-layer name=cnn5 $cnn_opts height-in=20 height-out=10 height-subsample-out=2 time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=256
  conv-relu-batchnorm-layer name=cnn6 $cnn_opts height-in=10 height-out=10  time-offsets=-1,0,1 height-offsets=-1,0,1 num-filters-out=256
  # the first TDNN-F layer has no bypass (since dims don't match), and a larger bottleneck so the
  # information bottleneck doesn't become a problem.  (we use time-stride=0 so no splicing, to
  # limit the num-parameters).
  tdnnf-layer name=tdnnf7 $tdnnf_first_opts dim=1536 bottleneck-dim=256 time-stride=0
  tdnnf-layer name=tdnnf8 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf9 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf10 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf11 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf12 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf13 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf14 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf15 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf16 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3
  tdnnf-layer name=tdnnf17 $tdnnf_opts dim=1536 bottleneck-dim=160 time-stride=3   
  linear-component name=prefinal-l dim=256 $linear_opts
  ## adding the layers for chain branch
  prefinal-layer name=prefinal-chain input=prefinal-l $prefinal_opts small-dim=256 big-dim=1536
  output-layer name=output include-log-softmax=false dim=$num_targets $output_opts
  # adding the layers for xent branch
  prefinal-layer name=prefinal-xent input=prefinal-l $prefinal_opts small-dim=256 big-dim=1536
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor $output_opts
EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi

if [ $stage -le 19 ]; then

  steps/nnet3/chain/train.py --stage $train_stage \
    --cmd "$decode_cmd" \
    --feat.online-ivector-dir exp/nnet3/ivectors_train_sp_aug_hires \
    --feat.cmvn-opts="--config=conf/online_cmvn.conf" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.0 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.add-option="--optimization.memory-compression-level=2" \
    --egs.dir "$common_egs_dir" \
    --egs.opts "--frames-overlap-per-eg 0 --constrained false --online-cmvn $online_cmvn" \
    --egs.stage $get_egs_stage \
    --egs.chunk-width $frames_per_eg \
    --trainer.num-chunk-per-minibatch 128,64 \
    --trainer.frames-per-iter 3000000 \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial $num_jobs_initial \
    --trainer.optimization.num-jobs-final $num_jobs_final \
    --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
    --trainer.optimization.final-effective-lrate $final_effective_lrate \
    --trainer.max-param-change $max_param_change \
    --cleanup.remove-egs $remove_egs \
    --feat-dir data/train_sp_aug_hires \
    --tree-dir $treedir \
    --lat-dir ${lat_dir} \
    --dir $dir  || exit 1;
    
fi


if [ $stage -le 20 ]; then
  utils/mkgraph.sh --self-loop-scale 1.0 data/lang $dir $dir/graph
fi

graph_dir=$dir/graph

if [ $stage -le 22 ]; then

  for test in {intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts}.{devset,testset}; do
       steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0  \
          --nj ${decode_nj} --cmd "$decode_cmd" $iter_opts \
          --online-ivector-dir exp/nnet3/ivectors_${test} \
         $graph_dir data/${test}_hires \
         $dir/decode_${test} &
      
  done  
  wait

fi

if [ $stage -le 30 ]; then
  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_large $dir $dir/graph_large
fi

graph_dir=$dir/graph_large

if [ $stage -le 32 ]; then

  for test in {intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts}.{devset,testset}; do
       steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0  \
          --nj ${decode_nj} --cmd "$decode_cmd" $iter_opts \
          --online-ivector-dir exp/nnet3/ivectors_${test} \
         $graph_dir data/${test}_hires \
         $dir/decode_${test}_large &
      
  done  
  wait

fi

if [ $stage -le 34 ]; then

  for test in {intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts}.{devset,testset}; do
       steps/lmrescore_const_arpa.sh \
           --cmd "$decode_cmd" \
         data/lang_large data/lang_larger \
         data/${test}_hires $dir/decode_${test}_large $dir/decode_${test}_large_rescore_larger &      
  done  
  wait

fi




export LD_LIBRARY_PATH=${KALDI_ROOT}/tools/openfst/lib/fst

if [ $stage -le 40 ]; then
  rm -rf $dir/graph_larger_lookahead
  utils/mkgraph_lookahead.sh --self-loop-scale 1.0 \
    data/lang_larger $dir $dir/graph_larger_lookahead
fi    

if [ $stage -le 42 ]; then

  for test in {intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts}.{devset,testset}; do
       steps/nnet3/decode_lookahead.sh --acwt 1.0 --post-decode-acwt 10.0  --stage 0 \
          --nj ${decode_nj} --cmd "$decode_cmd" $iter_opts \
          --online-ivector-dir exp/nnet3/ivectors_${test} \
         $dir/graph_larger_lookahead data/${test}_hires \
         $dir/decode_${test}_larger_lookahead &
      
  done  
  wait

fi

if [ $stage -le 50 ]; then
  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_larger $dir $dir/graph_larger
fi

graph_dir=$dir/graph_larger

if [ $stage -le 52 ]; then

  for test in {intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts,aktuaalne2021}.{devset,testset}; do
       steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0  \
          --nj ${decode_nj} --cmd "$decode_cmd" $iter_opts \
          --online-ivector-dir exp/nnet3/ivectors_${test} \
         $graph_dir data/${test}_hires \
         $dir/decode_${test}_larger &
      
  done  
  wait

fi

if [ $stage -le 60 ]; then
  utils/mkgraph.sh --self-loop-scale 1.0 data/lang_larger_unk $dir $dir/graph_larger_unk
fi

graph_dir=$dir/graph_larger_unk

if [ $stage -le 62 ]; then

  for test in {intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts,aktuaalne2021}.{devset,testset}; do
       steps/nnet3/decode.sh --stage 3 --acwt 1.0 --post-decode-acwt 10.0  \
          --nj ${decode_nj} --cmd "$decode_cmd" $iter_opts \
          --online-ivector-dir exp/nnet3/ivectors_${test} \
         $graph_dir data/${test}_hires \
         $dir/decode_${test}_larger_unk &
      
  done  
  wait

fi



if [ $stage -le 70 ] && $run_rnnlm_rescore; then

  for test in {intervjuud,jutusaated,ak,er,paevakaja,ekskfk,konverentsid,seeniorid,www-trans,podcasts,aktuaalne2021}.{devset,testset}; do

      rnnlm/lmrescore_pruned.sh \
        --cmd "$decode_cmd" \
        --weight 0.5 --max-ngram-order 4 --max-arcs 20000 --lattice-prune-beam 4 \
        data/lang_larger_unk \
        exp/rnnlm/rnnlm_lstm_1a \
        data/${test}_hires \
        $dir/decode_${test}_larger_unk \
        $dir/decode_${test}_larger_rnnlm_unk &
  done
  wait
fi
