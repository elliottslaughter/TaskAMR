--Copyright (c) 2018, Triad National Security, LLC
--All rights reserved.

--This program was produced under U.S. Government contract 89233218CNA000001 for
--Los Alamos National Laboratory (LANL), which is operated by Triad National
--Security, LLC for the U.S. Department of Energy/National Nuclear Security
--Administration.

--THIS SOFTWARE IS PROVIDED BY TRIAD NATIONAL SECURITY, LLC AND CONTRIBUTORS "AS
--IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
--IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
--DISCLAIMED. IN NO EVENT SHALL TRIAD NATIONAL SECURITY, LLC OR CONTRIBUTORS BE
--LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
--CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
--SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
--INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
--CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
--ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
--POSSIBILITY OF SUCH DAMAGE.
 
--If software is modified to produce derivative works, such modified software should be
--clearly marked, so as not to confuse it with the version available from LANL.

-- 1d AMR grid meta programming for all models
import "regent"
local C = regentlib.c

-- implement all required model APIs and link model.rg to your file
require("model")
require("model_amr")
require("1d_make_levels")
require("1d_make_amr")

-- meta programming to create top_level_task
function make_top_level_task()

  -- arrays of region by level
  local meta_region_for_level = terralib.newlist()
  local cell_region_for_level = terralib.newlist()
  local face_region_for_level = terralib.newlist()
  local meta_partition_for_level = terralib.newlist()
  local cell_partition_for_level = terralib.newlist()
  local face_partition_for_level = terralib.newlist()
  local bloated_partition_for_level = terralib.newlist()  -- refactor to "cell"
  local bloated_meta_partition_for_level = terralib.newlist()
  local parent_cell_partition_for_level = terralib.newlist()
  local parent_meta_partition_for_level = terralib.newlist()
  local bloated_parent_meta_partition_for_level = terralib.newlist()
  local bloated_cell_partition_by_parent_for_level = terralib.newlist()

  -- array of region and partition declarations
  local declarations = declare_level_regions(meta_region_for_level,
                                             cell_region_for_level,
                                             face_region_for_level,
                                             meta_partition_for_level,
                                             cell_partition_for_level,
                                             face_partition_for_level,
                                             bloated_partition_for_level,
                                             bloated_meta_partition_for_level,
                                             MAX_REFINEMENT_LEVEL,
                                             NUM_PARTITIONS)

  -- meta programming to initialize num_cells per level
  local num_cells = regentlib.newsymbol(int64[MAX_REFINEMENT_LEVEL+1], "num_cells")
  local dx = regentlib.newsymbol(double[MAX_REFINEMENT_LEVEL+1], "dx")
  local level_needs_regrid = regentlib.newsymbol(int64[MAX_REFINEMENT_LEVEL+1], "level_needs_regrid")
  local needs_regrid = regentlib.newsymbol(int64, "needs_regrid")
  local init_num_cells = make_init_num_cells(num_cells,
                                             dx,
                                             level_needs_regrid,
                                             MAX_REFINEMENT_LEVEL,
                                             cell_region_for_level)

  local init_activity = make_init_activity(meta_region_for_level)

  local write_cells = make_write_cells(num_cells,
                                       meta_partition_for_level,
                                       cell_partition_for_level)

  insert_parent_partitions(parent_cell_partition_for_level,
                           parent_meta_partition_for_level,
                           bloated_parent_meta_partition_for_level,
                           bloated_cell_partition_by_parent_for_level)

  local init_parent_partitions = initialize_parent_partitions(cell_partition_for_level,
                                                              cell_region_for_level,
                                                              parent_cell_partition_for_level,
                                                              meta_partition_for_level,
                                                              meta_region_for_level,
                                                              parent_meta_partition_for_level,
                                                              bloated_parent_meta_partition_for_level,
                                                              bloated_cell_partition_by_parent_for_level,
                                                              num_cells)

  local init_regrid_and_values = make_init_regrid_and_values(num_cells,
                                                             dx,
                                                             cell_partition_for_level,
                                                             bloated_partition_for_level,
                                                             face_partition_for_level,
                                                             meta_partition_for_level,
                                                             meta_region_for_level)

  local init_grid_refinement = make_init_grid_refinement(num_cells,
                                                         cell_partition_for_level,
                                                         meta_partition_for_level,
                                                         bloated_meta_partition_for_level,
                                                         parent_meta_partition_for_level,
                                                         parent_cell_partition_for_level,
                                                         bloated_parent_meta_partition_for_level,
                                                         meta_region_for_level)

  local time_step = make_time_step(num_cells,
                                   dx,
                                   cell_region_for_level,
                                   face_partition_for_level,
                                   cell_partition_for_level,
                                   meta_partition_for_level,
                                   bloated_partition_for_level,
                                   bloated_cell_partition_by_parent_for_level,
                                   parent_cell_partition_for_level)

  local flag_regrid = make_flag_regrid(num_cells,
                                       dx,
                                       level_needs_regrid,
                                       needs_regrid,
                                       face_partition_for_level,
                                       meta_partition_for_level,
                                       bloated_partition_for_level,
                                       bloated_cell_partition_by_parent_for_level)

  local do_regrid = make_do_regrid(num_cells,
                                   meta_region_for_level,
                                   cell_region_for_level,
                                   meta_partition_for_level,
                                   cell_partition_for_level,
                                   parent_cell_partition_for_level,
                                   parent_meta_partition_for_level,
                                   bloated_partition_for_level,
                                   bloated_cell_partition_by_parent_for_level,
                                   bloated_parent_meta_partition_for_level,
                                   bloated_meta_partition_for_level
                                   )

  local print_grid = make_print_grid(meta_partition_for_level,
                                     cell_partition_for_level)


  -- top_level task using previous meta programming
  local task top_level()

    -- test inputs
    if CELLS_PER_BLOCK_X < 2 then
      C.printf("\n ERROR: CELLS_PER_BLOCK_X must be at least 2!\n\n")
      C.exit(1)
    end

    if (CELLS_PER_BLOCK_X % 2) == 1 then
      C.printf("\n ERROR: CELLS_PER_BLOCK_X must be a multiple of 2!\n\n")
      C.exit(1)
    end

    [declarations];
    [init_num_cells];
    [init_parent_partitions];
    [init_activity];

    for level = 1, MAX_REFINEMENT_LEVEL + 1 do
      [dx][level] = LENGTH_X / [double]([num_cells][level])
      C.printf("Level %d cells %d dx %e\n", level, [num_cells][level], [dx][level])
    end

    [init_regrid_and_values];
    [init_grid_refinement];

    var [needs_regrid]

    var time : double = 0.0
    while time < T_FINAL - DT do 

      [time_step];
      [flag_regrid];

      if [needs_regrid] > 0 then
        [do_regrid];
      end
 
      time += DT
      C.printf("time = %f\n",time)
    end
    [write_cells];
  end
  return top_level
end

-- top level task

local top_level_task = make_top_level_task()
regentlib.start(top_level_task)

