#! /usr/bin/env python

import sys
import io
import argparse
import xml
import xml.etree.ElementTree as ET
import fileinput
import re

def add_segment(reco, spk, start_time, end_time, text, segments, utt2spk):
  segment_id = f"{reco}###{spk}###{start_time:08.3f}-{end_time:08.3f}"
  
  if len(text) > 0 and start_time < end_time:
    segments.append((segment_id, reco, start_time, end_time, text))  
    utt2spk[segment_id] = f"{reco}###{spk}"
  

if __name__ == '__main__':

  parser = argparse.ArgumentParser(description='Convert Transcriber *.trs files to Kaldi data dir')
  parser.add_argument("datadir", help='Kaldi data dir for putting the results')
  parser.add_argument("reco2trs")
  args = parser.parse_args()

  spk2name = {}
  segments = []
  utt2spk = {}


  for l in open(args.reco2trs):    
    reco, trs = l.split()
    root = ET.parse(trs).getroot()    
    
    speakers = root.findall("Speakers/Speaker")
    for speaker in speakers:
      spk2name[f"{reco}###{speaker.attrib['id']}"] = speaker.attrib["name"]
    
    turns = root.findall('**/Turn')
    for turn in turns:
      if "speaker" in turn.attrib:
        current_start = float(turn.attrib["startTime"])
        turn_end = float(turn.attrib["endTime"])
        current_text = []
        spk = turn.attrib["speaker"]
        # skip overlapping regions
        if len(spk.split()) > 1:
          continue        
        for el in turn.iter():
          if el.tag == "Sync":
            sync_time = float(el.attrib["time"])
            if sync_time != current_start:            
              add_segment(reco, spk, current_start, sync_time, " ".join(current_text), segments, utt2spk)
            current_start = sync_time
            current_text = []
          elif el.tag == "Event":
            if el.attrib["type"] == "noise" and el.attrib["extent"] == "instantaneous":
              if el.attrib["desc"] in ["r", "i", "b", "n", "pf"]:
                current_text.append("<v-noise>")
          text = el.tail.strip().replace("\n", " ")       
          if len(text) > 0:
             current_text.append(text)
        if turn_end != current_start:            
          add_segment(reco, spk, current_start, turn_end, " ".join(current_text), segments, utt2spk)
          
  with open(f"{args.datadir}/segments", "w") as f:   
    for segment in sorted(segments):
      print(f"{segment[0]} {segment[1]} {segment[2]} {segment[3]}", file=f)

  with open(f"{args.datadir}/text", "w") as f:   
    for segment in sorted(segments):
      print(f"{segment[0]} {segment[4]}", file=f)

  with open(f"{args.datadir}/utt2spk", "w") as f:   
    for utt, spk in sorted(utt2spk.items()):      
      print(f"{utt} {spk}", file=f)

  with open(f"{args.datadir}/spk2name", "w") as f:   
    for spk, name in sorted(spk2name.items()):
      print(f"{spk} {name}", file=f)
      
