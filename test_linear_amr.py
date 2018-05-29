#!/usr/bin/python
# Copyright (c) 2018, Los Alamos National Security, LLC
# All rights reserved.
#
# Copyright 2018. Los Alamos National Security, LLC. This software was produced under
# U.S. Government contract DE-AC52-06NA25396 for Los Alamos National Laboratory (LANL),
# which is operated by Los Alamos National Security, LLC for the U.S. Department of
# Energy. The U.S. Government has rights to use, reproduce, and distribute this
# software.  NEITHER THE GOVERNMENT NOR LOS ALAMOS NATIONAL SECURITY, LLC MAKES ANY
# WARRANTY, EXPRESS OR IMPLIED, OR ASSUMES ANY LIABILITY FOR THE USE OF THIS SOFTWARE.
# If software is modified to produce derivative works, such modified software should be
# clearly marked, so as not to confuse it with the version available from LANL.
#
import numpy as np
import os
import subprocess
import sys
from analyze_linear import trapezoid
from analyze_amr_linear import read_amr
from test_linear import set_refinement_level

legion_root = os.environ.get('LEGION_ROOT', '../../github/legion')
regent = os.path.join(legion_root, 'language/regent.py')

def set_cells_per_block_x(cells_per_block_x):
  with open("global_const.rg","w") as f:
    f.write("-- required global constants\n")
    f.write("CELLS_PER_BLOCK_X = "+str(cells_per_block_x)+"\n")
    f.write("LEVEL_1_BLOCKS_X = 5\n")
    f.write("MAX_REFINEMENT_LEVEL = 1\n")
    f.write("NUM_PARTITIONS = 7\n")
    f.write("T_FINAL = 0.25\n")
    f.write("LENGTH_X = 1.0\n")
    f.close()

def test_amr(refinement_level, filenames, threshold, descriptor):
  ERROR = 0
  with open("/dev/null","w") as dev_null:

    set_refinement_level(refinement_level)
    subprocess.check_call([regent,'1d_amr.rg','-ll:cpu','2'], stdout=dev_null)

    x, numeric = read_amr(filenames)
    x = np.array(x)
    analytic = np.zeros(len(x))
    analytic[np.where(np.array(x)<0.75)] = 1.0
    L2 = trapezoid(x, (numeric - analytic)**2)
 
    if (L2 > threshold) or np.isnan(L2) :
      print descriptor+": \033[0;31mFAIL\033[0m ",L2," > ",threshold
      ERROR = 1
    else:
      print descriptor+": \033[0;32mPASS\033[0m",L2," < ",threshold
  return ERROR

if __name__== "__main__":

  subprocess.check_call(["ln","-sf","linear_advection.rg","model.rg"])
  subprocess.check_call(["ln","-sf","linear_advection_amr.rg","model_amr.rg"])

  set_cells_per_block_x(0)
  with open("/dev/null","w") as dev_null:
    ERROR = subprocess.call([regent,"1d_amr.rg"], stdout=dev_null)
  if ERROR == 0:
    print "1d_amr CELLS_PER_BLOCK_X: \033[0;31mFAIL\033[0m"
    sys.exit(1)

  set_cells_per_block_x(3)
  with open("/dev/null","w") as dev_null:
    ERROR = subprocess.call([regent,"1d_amr.rg"], stdout=dev_null)
  if ERROR == 0:
    print "1d_amr CELLS_PER_BLOCK_X: \033[0;31mFAIL\033[0m"
    sys.exit(1)

  sys.exit(test_amr(4, ["linear_amr.20.0.txt", "linear_amr.40.0.txt","linear_amr.40.3.txt",
                        "linear_amr.80.6.txt","linear_amr.80.12.txt","linear_amr.80.18.txt",
                        "linear_amr.80.24.txt","linear_amr.80.30.txt","linear_amr.80.36.txt"],
                    0.0502553, "AMR 4 levels"))
