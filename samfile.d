/*
    This file is part of Sambamba.
    Copyright (C) 2012    Artem Tarasov <lomereiter@gmail.com>

    Sambamba is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    Sambamba is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

*/
module samfile;

import std.stdio;
import std.array;
import std.string;

import alignment;
import samheader;
import reference;
import sam.recordparser;

struct SamFile {

    this(string filename) {
        _initializeStream(filename);
    }

    SamHeader header() @property {
        return _header;
    }

    ReferenceSequenceInfo[] reference_sequences() @property {
        return _reference_sequences;
    }

    auto alignments() @property {
        struct Result {
            this(File file, ref SamHeader header) {
                _file = file;
                _header = header;
                _line_range = file.byLine();

                _build_storage = new AlignmentBuildStorage();
            }
            
            bool empty() @property {
                return _line_range.empty;
            }
            
            void popFront() @property {
                _line_range.popFront();
            }

            Alignment front() @property {
                return parseAlignmentLine(cast(string)_line_range.front, _header,
                                          _build_storage);
            }

            private {
                alias File.ByLine!(char, char) LineRange;
                LineRange _line_range;
                SamHeader _header;

                AlignmentBuildStorage _build_storage;
            }
            
            private:
            File _file;
            char[] buffer;
        }
        return Result(_file, _header);
    }
private:

    File _file;

    ulong _header_end_offset;

    SamHeader _header;
    ReferenceSequenceInfo[] _reference_sequences;

    void _initializeStream(string filename) {
        _file = File(filename); 

        char[] _buffer;

        auto header = appender!(char[])(); 
        while (_file.isOpen && !_file.eof()) {
            _header_end_offset = _file.tell();
            auto read = _file.readln(_buffer);
            auto line = _buffer[0 .. read];

            if (line.length > 0 && line[0] == '@') {
                header.put(line);
            } else {
                if (line.length > 0) {
                    _file.seek(_header_end_offset);
                    break;
                }
            }
        }

        _header = new SamHeader(cast(string)(header.data));

        _reference_sequences = new ReferenceSequenceInfo[_header.sequences.length];
        foreach (sq; _header.sequences) {
            ReferenceSequenceInfo seq;
            seq.name = sq.name;
            seq.length = sq.length;
            _reference_sequences[_header.getSequenceIndex(seq.name)] = seq;
        }
    }
}
