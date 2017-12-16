/*
    This file is part of Sambamba.
    Copyright (C) 2017 Pjotr Prins <pjotr.prins@thebird.nl>

    Sambamba is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published
    by the Free Software Foundation; either version 2 of the License,
    or (at your option) any later version.

    Sambamba is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
    02111-1307 USA

*/
module sambamba.subsample;

/**

   Subsampling.

   Subsampling limits the read depth to a certain threshold. This is
   increasingly important with large sequencing efforts where high
   depth can be reached, especially in non-informative regions - i.e.,
   with high repeats. A good subsample method does not have to be
   exact (we can vary around the maximum read depth) but has to be
   reproducible and limit effect on down stream variant calling.

   The first algorithm 'hash1' is the same one used in
   VariantBam::SubSampleWrite. It simply takes the coverages at the
   beginning and end of a read, takes the maximum and drops reads
   based on a Hash computation (you end up with an approximate number
   of reads around max_depth). This algorithm is reproducible but does
   not consider other factors and read pairs.

   Authors: Pjotr Prins and Brad Chapman

 */

import std.experimental.logger;
import std.getopt;
import std.parallelism;
import std.range;
import std.stdio;
import std.typecons;

import sambamba.bio2.bam.reader;
import sambamba.bio2.bgzf;
import sambamba.bio2.constants;
import sambamba.bio2.pileup;

void printUsage() {
  writeln("
Usage: sambamba subsample [options] <input.bam> [<input2.bam> [...]]

       Subsample a bam file.

Options:

         --type [hash1]  Algorithm for subsampling (hash1, default is none)
         --logging type  Set logging to debug|info|warning|critical
");
}

/**
   For every read track position
*/
struct ReadInfo {
  RefId ref_id;
  GenomePos start_pos, end_pos;

  this(ref ProcessReadBlob read) {
    ref_id = read.ref_id;
    start_pos = read.start_pos;
    end_pos = read.end_pos;
  }
}

/**
   Implementation of Hash1. While reads stream in they get piled up in
   a ringbuffer. The ringbuffer gets filled ahead until the read that is
   no longer overlapping, creating a window:

                                                          r-------------
                                               ----y---------------
                                        -----------y--------
                                 x=================y
                            -----x-------------
                   --------------x----
              l------------------x-----
          leftmost             start_pos       end_pos  rightmost

   once the reads have been counted it moves to the next read, reads ahead
   and destroys the leftmost reads that have gone out of the window.
*/
int subsample_main(string[] args) {
  globalLogLevel(LogLevel.trace); // debug level

  if (args.length < 2) {
    printUsage();
    return 1;
  }

  auto infns = args[1..$];

  auto pileup = new PileUp!ProcessReadBlob();

  foreach (string fn; infns) {
    auto stream = BamReadBlobStream(fn);

    // get the first two reads
    auto current = ProcessReadBlob(stream.read);
    auto current_idx = pileup.push(current);
    assert(current_idx == 0);
    auto rightmost = current;
    auto prev_rightmost = current;
    auto leftmost = current;
    auto leftmost_idx = current_idx;

    while (true) { // loop through pileup
      assert(!current.isNull);
      // Fill ring buffer ahead until the window is full (current and rightmost)
      // rightmost is null at the end
      while (!rightmost.isNull && current.ref_id == rightmost.ref_id && rightmost.start_pos < current.end_pos+1) {
        rightmost = ProcessReadBlob(stream.read);
        if (rightmost.isNull)
          break;
        prev_rightmost = rightmost;
        pileup.push(rightmost);
      }

      // Now we have a pileup and we can check this read (output)
      writeln("     start  at ",leftmost.ref_id," ",leftmost.start_pos,":",leftmost.end_pos);
      //writeln("---> pileup at ",current.ref_id," ",current.start_pos,":",current.end_pos);
      if (!rightmost.isNull)
        writeln("     ending at ",rightmost.ref_id," ",rightmost.start_pos,":",rightmost.end_pos);
      else
        writeln("     reached end ",pileup.ring.length());
      // Compute depth

      // Are we actually on the last read? (current and prev_rightmost)
      if (rightmost.isNull && current == prev_rightmost)
        break;

      // Move to next (current)
      current_idx = pileup.get_next_idx(current_idx);
      current = pileup.read_at_idx(current_idx);
      if (current.isNull)
        break;

      // Remove leading reads (leftmost and current)
      while (leftmost.ref_id != current.ref_id || leftmost.end_pos < current.start_pos) {
        leftmost_idx = pileup.popFront();
        leftmost = pileup.front;
      }
      assert(!pileup.empty);
    }
  }
  return 0;
}
