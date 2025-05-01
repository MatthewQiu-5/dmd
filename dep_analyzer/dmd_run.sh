#!/bin/bash

dub run -- "/home/matthewqiu/dlang-repo/dmd/compiler/src/dmd" "/home/matthewqiu/dlang-repo/dep_analyzer/source/dmd_restricted"
dot -Tsvg dependency_graph.dot -o dependency_graph.svg
