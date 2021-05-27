#! /usr/bin/env python3

import sys

out_lines = []

current = None

for l in sys.stdin:
  ss = l.split()
  word = ss[4]
  if word.startswith("__"):
    word = word[2:]
    if current is not None and current[0] == ss[0] and current[1] == ss[1]:
      current[4] += word
      current[3] = "%0.2f" % (float(ss[2]) + float(ss[3]) - float(current[2]))
    else:
      if current is not None:
        out_lines.append(current)
      current = ss        
  else:
    if current is not None:
      out_lines.append(current)
    current = ss

for l in out_lines:
  print(" ".join(l))
  

