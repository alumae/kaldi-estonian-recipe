#!/usr/bin/env bash

cmd=run.pl
nj=4

actions="process_fragments,remove_punctuation,split_compounds"

# End configuration section.


echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "usage: $0 input_text output_text logdir"
fi

input_text=$1
output_text=$2
logdir=$3

for n in $(seq $nj); do
  split_input_text="$split_input_text  ${input_text}.$n.tmp"
  split_output_text="$split_input_text ${output_text}.$n.tmp"
done
   
utils/split_scp.pl $input_text $split_input_text || exit 1;

$cmd JOB=1:$nj $logdir/preprocess_text.JOB.log \
  cat ${input_text}.JOB.tmp \| python3 local/preprocess_text.py --actions "${actions}" \> ${output_text}.JOB.tmp || exit 1;


## concatenate the  files together.
for n in $(seq $nj); do
  cat ${output_text}.$n.tmp || exit 1;
done > ${output_text} || exit 1;

rm -f ${split_input_text}
rm -f ${split_output_text}
