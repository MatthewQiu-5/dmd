module dep_analyzer;

import std.stdio;
import std.range;
import std.file;
import std.path;
import std.algorithm;
import std.getopt;
import std.container;

import util;

import dparse.ast;
import dparse.lexer;
import dparse.parser : parseModule;
import dparse.rollback_allocator : RollbackAllocator;

class ImportDeclarationVisitor : ASTVisitor
{
    alias visit = ASTVisitor.visit;
    string mCurrentModuleName;
    DependencyAnalyzer mDepsAnalyzer;

    this(string currentModuleName, DependencyAnalyzer da)
    {
        mCurrentModuleName = currentModuleName;
        mDepsAnalyzer = da;
    }

    override void visit(const ImportDeclaration id)
    {
        // Retrieve module name
        string imported_module;
        if (id.importBindings !is null)
        {
            imported_module = join(id.importBindings.singleImport.identifierChain.identifiers
                .map!(token => token.text), ".");
        }
        else
        {
            foreach (singleImport; id.singleImports)
            {
                imported_module = join(singleImport.identifierChain.identifiers.map!(token => token.text), ".");
            }
        }

        // Create new dependency
        // key = imported module
        // value = list of importers
        mDepsAnalyzer.mDependencies[imported_module] ~= mCurrentModuleName; 

        // Continue visitor traversal
        super.visit(id);
    }
}

class DependencyAnalyzer
{    
    string mBaseDir;
    // Makeshift hash-set for storing modules that have semantic dependencies
    int[string] mRestrictedModules; 

    // Dependencies
    string[][string] mDependencies;

    LexerConfig mConfig;
    StringCache mCache;

    bool mPruneFlag;

    this(string baseDirectory, string restrictedModulesPath, string pruneFlag)
    {
        if (pruneFlag == "no-prune")
        {
            mPruneFlag = false;
        } else {
            mPruneFlag = true;
        }
        mBaseDir = baseDirectory;
        mCache = StringCache(StringCache.defaultBucketCount);

        // Read in list of restricted modules
        File f = File(restrictedModulesPath);
        foreach(line; f.byLine)
        {
            mRestrictedModules[line.idup] = 0;
        }
    }

    void findDependencies()
    {
        // Process all .d files
        auto files = dirEntries(mBaseDir, SpanMode.depth).filter!(f => f.name.endsWith(".d"));
        foreach (f; files)
            processFile(f.name);

        if(mPruneFlag)
        {
            pruneNodes();
        }
    }

    void pruneNodes()
    {
        // Prunes nodes that do not rely on any of the restricted nodes.
        bool[string] visited;

        // Enqueue all restricted modules first
        auto queue = DList!string();
        foreach (r; mRestrictedModules.keys)
        {
            if (r in mDependencies)
            {
                queue.insertBack(r);
                visited[r] = true;
            }
        }

        // BFS
        while (!queue.empty)
        {
            string current = queue.front;
            queue.removeFront();
            
            if (current in mDependencies)
            {
                foreach (dep; mDependencies[current])
                {
                    if (dep !in visited)
                    {
                        visited[dep] = true;
                        queue.insertBack(dep);
                    }
                }
            }
        }

        // Remove all nodes not reachable from restricted modules
        string[] allNodes = mDependencies.keys;        
        foreach (node; allNodes)
        {
            if (node !in visited)
            {
                mDependencies.remove(node);
            }
        }
        
        // If a node wasn't visited, remove it from the adjacency list values
        foreach (node; mDependencies.keys)
        {
            mDependencies[node] = mDependencies[node].filter!(dep => dep in visited).array;
        }

    }

    void processFile(string file_path)
    {
        // Tokenize source code and then parse into AST
        string sourceCode = readText(file_path);
        auto tokens = getTokensForParser(sourceCode, mConfig, &mCache);
        RollbackAllocator rba;
        auto m = parseModule(tokens, file_path, &rba);
        
        // Get current module name
        string current_module_name = join(m.moduleDeclaration.moduleName.identifiers.map!(token => token.text), '.');
        current_module_name = truncateModuleName(current_module_name); 

        // Invoke import decl visitor
        ImportDeclarationVisitor idv = new ImportDeclarationVisitor(current_module_name, this);
        idv.visit(m);
    }

    void produceDotGraph() {

        // Generates Graphviz .dot graph schema for dependency graph
        string dot = "digraph " ~ "Dependencies" ~ " {\n";
        bool[string] presentRestrictedModules;

        // Set style to fill in color
        dot ~= "    node [style=filled];\n";

        // Create nodes (modules) and edges (imports)
        foreach (importedModule, importingList; mDependencies) {

            // Create edge between importing and imported module nodes
            if (importingList.length > 0) {

                // Check if imported module is restricted
                if (importedModule in mRestrictedModules)
                {
                    presentRestrictedModules[importedModule] = 0;
                }

                // Create edges for imports
                foreach (importingModule; importingList) {
                    dot ~= "    \"" ~ importedModule ~ "\" -> \"" ~ importingModule ~ "\";\n";
                    
                    // Check if importing module is restricted
                    if (importingModule in mRestrictedModules)
                    {
                        presentRestrictedModules[importingModule] = 0;
                    }
                }
            }
        }

        // Colors restricted modules light pink
        foreach(restrictedModule; presentRestrictedModules.keys)
        {
            dot ~= "    " ~ "\"" ~ restrictedModule ~ "\"" ~ " [fillcolor=lightpink];\n";
        }

        dot ~= "}\n";

        writeln(dot);

        std.file.write("dependency_graph.dot", dot);
    }
}

void main(string[] args)
{
    if (args.length < 4)
    {
        writeln("Execute program with 'dub -- path_to_target_directory path_to_restricted_modules_list prune_flag'");
    }

    DependencyAnalyzer da = new DependencyAnalyzer(args[1], args[2], args[3]);
    da.findDependencies();
    da.produceDotGraph();
}