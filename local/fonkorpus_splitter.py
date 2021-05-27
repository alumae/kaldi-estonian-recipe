# -*- coding: UTF-8 -*-

import argparse
import sys
import tgt
import os.path

def prettify_words(words):
  result = []
  for word in words:
    word = word.partition("/")[0]    
    if word in [u'.sisse', u'.välja']:
      result.append("<v-noise>")
      pass
    elif word in [u'.matsutus']:
      result.append("<v-noise>")
      pass
    elif word.startswith("."):
      result.append("<v-noise>")
      pass
    elif word == "#":
      pass      
    #elif word.endswith("-"):
    #  result.append("++garbage++")
    else:      
      if len(word) > 0 and word[-1] == "-":
        word = word[:-1] + "()"
      result.append(word.replace("+", ""))
  return result

if __name__ == '__main__':

  parser = argparse.ArgumentParser(description='Convert EKSKFK TextGrid files to Kaldi data directory')
  parser.add_argument("datadir", help='Kaldi data dir for putting the results')
  parser.add_argument("textgrid", nargs='+', help='TextGrid files in EKSKFK format')
  
  args = parser.parse_args()
  
  # pad utterances with that much of silence
  pad_length = 0.5 
  
  segments = []
  wavs = {}
  
  for f in args.textgrid:
    reco = os.path.basename(f).partition(".TextGrid")[0]
    wavs[reco] = f.partition(".TextGrid")[0] + ".wav"
    tg = tgt.io.read_textgrid(f, "utf-8")
    word_tier = tg.get_tier_by_name(u'sõnad')
    utt_tier = tg.get_tier_by_name(u'lausungid')
    
    utterances = utt_tier.get_annotations_with_text("JUTT")

    joined_utterances = []

    i = 0
    while i <= len(utterances) - 1:
      start_time = utterances[i].start_time - pad_length
      if start_time < 0:
        start_time = 0
      if i == len(utterances) - 1:
        end_time = utterances[i].end_time
      else:
        end_time = utterances[i].end_time + pad_length
      while i < len(utterances) - 1 and end_time >= utterances[i+1].start_time - pad_length:
        i += 1
        if i == len(utterances) - 1:
          end_time = utterances[i].end_time
        else:
          end_time = utterances[i].end_time + pad_length
      joined_utterances.append((start_time, end_time))
      i += 1
      

    for joined_utterance in joined_utterances:
      word_intervals = word_tier.get_annotations_between_timepoints(joined_utterance[0], joined_utterance[1])
      words = prettify_words([s.text for s in word_intervals])
      
      segment_id = f"{reco}###{joined_utterance[0]:08.3f}-{joined_utterance[1]:08.3f}"
      segments.append((segment_id, reco, joined_utterance[0], joined_utterance[1], " ".join(words)))
      #print(round(joined_utterance[0],2), round(joined_utterance[1],2), " ".join(words))

  with open(f"{args.datadir}/segments", "w") as f:   
    for segment in segments:
      print(f"{segment[0]} {segment[1]} {segment[2]:.3f} {segment[3]:.3f}", file=f)

  with open(f"{args.datadir}/text", "w") as f:   
    for segment in segments:
      print(f"{segment[0]} {segment[4]}", file=f)

  with open(f"{args.datadir}/utt2spk", "w") as f:   
    for segment in segments:      
      print(f"{segment[0]} {segment[1]}", file=f)
 
  with open(f"{args.datadir}/wav.scp", "w") as f:   
    for reco, wav in wavs.items():      
      print(f"{reco} sox {wav} -c 1 -b 16 -t wav - rate 16000 |", file=f)
 
