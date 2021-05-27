#! /usr/bin/env python

import argparse
import re
import sys
import logging

import estnltk
from estnltk.taggers import CompoundTokenTagger
from estnltk.taggers import TokensTagger
from estnltk.taggers import VabamorfTagger
from estnltk import Text

from tts_preprocess_et.convert import convert_sentence

import difflib

def tag_compounds(surface, morpho, roots):
    
    if surface == morpho:
      return surface
      
    sm = difflib.SequenceMatcher(a=surface, b=morpho, autojunk=False)
    r = surface
    d = 0
    for o in sm.get_opcodes():
      if o[0] == 'insert' and sm.b[o[3]] in ["_"]:
        r = r[0:o[2] + d] + sm.b[o[3]] + r[o[2]+d:]
        d += 1
      if o[0] == 'replace' and sm.b[o[3]] in ["_"]:
        r = r[0:o[2] + d] + sm.b[o[3]] + r[o[2]+d:]
        d += 1
    
    if r[0] != morpho[0] and r[0].lower() == morpho[0] and len(morpho) > 1 and r[1] == morpho[1]:
      r = r.lower()

    return r


class Processor():
  def __init__(self):
    self.tokens_tagger = TokensTagger()
    self.compound_token_tagger = CompoundTokenTagger()
    self.morph_tagger = VabamorfTagger()
    self.non_estonian_block = False
    
  
  def process(self, line, actions, target):
    if "filter_text" in actions:
      # remove non-estonian text
      if line.startswith("<doc") and "lang_old2=" in line and not 'lang_old2="estonian"' in line:
        self.non_estonian_block = True
        return None        
      elif line.startswith("</doc") and self.non_estonian_block:
        self.non_estonian_block = False
        return None      
      elif self.non_estonian_block:
        return None      
      if line.startswith("<doc") or line.startswith("</doc"):              
        return None
        
    if "numbers2text" in actions:
      if not (line.startswith("<doc") or line.startswith("</doc")):      
        line = convert_sentence(line, convert_target='asr_lm')
    
    if "process_fragments" in actions:      
      line = re.sub(r"\(\)", "<fragment ()>", re.sub(r"\(\S*\)(\w+)", r"<fragment -\1>", re.sub(r"(\S+)\(\w*\)", r"<fragment \1->", line)))
      
    text = Text(line)
    #self.tokens_tagger.tag(text)
    #self.compound_token_tagger.tag(text)
    #self.morph_tagger.tag(text)
    text.tag_layer(['tokens',  'compound_tokens', 'morph_analysis'])
    result = []
    
    for word in text.morph_analysis:
      surface = word["normalized_text"][0]
      morpho =  word["root"][0]
      roots = word["root_tokens"][0]
      partofspeech = word["partofspeech"][0]
      if "remove_punctuation" in actions and partofspeech == "Z":
        if surface in ["(", ")"] and target == "stm":
          result.append(surface)
          continue
        else:
          continue
      #print("--->", surface, morpho, roots)
      
      tagged = tag_compounds(surface, morpho, roots)
      if "split_compounds" in actions:
        if not (line.startswith("<doc") or line.startswith("</doc")):      
          if not tagged.startswith("<"):
            tagged = tagged.replace("_", " +C+ ")                      
            tagged = re.sub("(\S)-(\S)", r"\1 +D+ \2", tagged)
          
        
      if tagged.startswith("<fragment"):
        if target == "lm":
          # remove fragments
          tagged = None
        elif target == "am":
          tagged = "<unk>"
        elif target == "stm":
          tagged = tagged[len("<fragment "):-1]
          #pass
          
      if tagged is not None:  
        result.append(tagged)
      
    result_text = " ".join(result)
    if "remove_punctuation" in actions and target == "stm":
      result_text = re.sub("\( (\S*) *\)", r"(\1)", result_text)
      
    return result_text
      

if __name__ == '__main__':
  logging.basicConfig(stream=sys.stderr, level=logging.DEBUG)
  parser = argparse.ArgumentParser(description='Preprocess Estonian text for ASR ')
  
  parser.add_argument("--actions", default="process_fragments,remove_punctuation,split_compounds")
  parser.add_argument("--num-skip-fields", type=int, default=0)  
  parser.add_argument("--target", choices=['am', 'lm', 'stm'], default="am")
  #parser.add_argument("in_text")
  #parser.add_argument("out_text")
  args = parser.parse_args()
  p = Processor()
  
  actions = [s.strip() for s in args.actions.split(",")]
  for l in sys.stdin:
    ss = l.split()
    header = " ".join(ss[:args.num_skip_fields])
    content = " ".join(ss[args.num_skip_fields:])
    try:
      result = p.process(content, actions, args.target)
      if result is not None:
        if len(header) > 0:
          print(header,  end=" ")
        print(result)
    except:
      logging.exception("Failed convert line [%s]: " % content,  stack_info=True)
