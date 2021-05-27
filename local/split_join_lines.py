#! /usr/bin/env python

import argparse
import re
import sys
import logging
import random
import textwrap

if __name__ == '__main__':
  logging.basicConfig(stream=sys.stderr, level=logging.DEBUG)
  parser = argparse.ArgumentParser(description='Randomly joins short text lines and splits long lines')
  
  parser.add_argument("--short", default=60, type=int)
  parser.add_argument("--long", default=200, type=int)
  parser.add_argument("--join-probability", type=float, default=0.7)  
  parser.add_argument("--split-probability", type=float, default=0.5)  
  args = parser.parse_args()
  
  current_line = None
  for l in sys.stdin:
    l = l.strip()
    if current_line is None:
      if len(l) < args.short:
        current_line = l
      else:
        if len(l) > args.long and random.random() < args.split_probability:
          l = textwrap.fill(l, args.long)
        print(l)
    else:
      if len(l) < args.short:
        if random.random() < args.join_probability:
          current_line += " "
          current_line += l
        else:
          print(current_line)
          current_line = l
      else:
        print(current_line)
        print(l)
