#!/bin/bash

dub run -- "/home/matthewqiu/dlang-repo/dmd/dep_analyzer/example_dir" "/home/matthewqiu/dlang-repo/dmd/dep_analyzer/source/restricted_files" "prune"
dot -Tpng dependency_graph.dot -o dependency_graph.png
