# bio-hpc-gff3

[![Build Status](https://secure.travis-ci.org/mamarjan/bioruby-hpc-gff3.png)](http://travis-ci.org/mamarjan/bioruby-hpc-gff3)

Note: this software is under active development!

This is currently an early work in progress to create a parallel GFF3
and GTF parser library for D and a Ruby gem which would take advantage
of that library.

## Installation


TODO: Write scripts for installation.

### Run tests

A D compliler is required to run the tests.

If you are using homebrew on OsX you can install dmd like so:

$ brew install dmd


Currently only D unit tests are working. You can run them using the
"unittests" rake task, like this:

```sh
    rake unittests
```

## Usage

```ruby
    require 'bio-hpc-gff3'
```

TODO: Generate API docs and find a nice place for them somewhere on
the net.

The API doc is online. For more code examples see the test files in
the source tree.

### GFF3 File validation

The validation utility can be built using the "validator" rake task,
like this:

```sh
    rake validator
```

The result will be in the root directory, and can be used like this:

```sh
    ./validate-gff3 path/to/file.gff3
```

### Benchmarking utility

There is a small D application for performance benchmarking, you can
build it using:

```sh
    rake benchmark
```

And then run it like this:

```sh
    ./benchmark-gff3 path/to/file.gff3
```

The most basic case for the banchmarking utility is to parse the
file into records. More functionality is available using command
line options:

```
  -v     turn on validation
  -r     turn on replacement of escaped characters
  -f     merge records into features
  -c N   feature cache size (how many features to keep in memory), default=1000
  -l     link feature into parent-child relationships
```
        
## Project home page

Information on the source tree, documentation, examples, issues and
how to contribute, see

  http://github.com/mamarjan/bioruby-hpc-gff3

The BioRuby community is on IRC server: irc.freenode.org, channel: #bioruby.

## Cite

If you use this software, please cite one of
  
* [BioRuby: bioinformatics software for the Ruby programming language](http://dx.doi.org/10.1093/bioinformatics/btq475)
* [Biogem: an effective tool-based approach for scaling up open source software development in bioinformatics](http://dx.doi.org/10.1093/bioinformatics/bts080)

## Biogems.info

This Biogem is published at [#bio-hpc-gff3](http://biogems.info/index.html)

## Copyright

Copyright (c) 2012 Marjan Povolni. See LICENSE.txt for further details.

