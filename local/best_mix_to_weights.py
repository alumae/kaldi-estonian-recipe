#! /usr/bin/env python

import numpy as np
import os
import sys

names = []
weights = []

threshold = 0.01
best_mix = sys.stdin.readline()
ss = best_mix.split()
for i in range(len(ss)//4):
  name = ss[i*4+1]
  weight = float(ss[i*4+3])
  if weight >= threshold:
    names.append(os.path.basename(name).partition(".")[0])
    weights.append(weight)
    
weights = np.array(weights)
weights = weights / sum(weights)    
    
for i in range(len(names)):
  print("%s 1 %f" % (names[i], weights[i]))


