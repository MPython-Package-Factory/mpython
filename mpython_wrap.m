function [fnstr, initstr, hashmap] = mpython_wrap(path, opath, dirname, overwrite, templatedir, ispackage, istoplevel, isclass, isprivate, clsname)
    global PKGNAME; 
    if nargin < 4
        overwrite = false; 
    end
    if nargin < 5
        templatedir = '';
    end
    if nargin < 6
        ispackage = true;
    end
    if nargin < 7
        istoplevel = ispackage;
    end
    if nargin < 8
        isclass = false; 
    end
    if nargin < 9
        isprivate = false; 
    end
    if nargin < 10
        clsname = '';
    end

    dirname = strrep(dirname, '-', '_');
    dirname = strrep(dirname, '.', '_');

    % top level folder 
    if istoplevel

        clear global PKGNAME ;
        global PKGNAME; 
        PKGNAME = dirname; 

        clear global TEMPLATES; 
        global TEMPLATES; 
        TEMPLATES = mpython_load_templates(templatedir);

        clear global ROOTPATH; 
        global ROOTPATH; 
        ROOTPATH = getfield(dir(path), 'folder'); 

        % create opath/
        if ~exist(opath, 'dir')
            mkdir(opath)
        end

        % create opath/setup.py
        if ~exist(fullfile(opath, 'setup.py', 'file'))
            mpython_create_setup(opath);
        end

        fprintf('Wrapping %s... \n', PKGNAME); 

        % to do: check for differences in the mpython script
        initstr = ['from .__wrapper__ import Struct, Cell' newline]; 
    else
        initstr = []; 
    end

    if ~isempty(regexp(path, ['.*?_' PKGNAME], 'match'))
        return 
    end

    if ~isclass && ~isprivate
        % create dirname
        opath = fullfile(opath, dirname); 
        if ~exist(opath, 'dir')
            mkdir(opath)
        end
    end

    if istoplevel
        mpython_create_wrapper(opath);
    end

    % get hashmap
    if overwrite
        hashmap = struct;
    else
        hashmap = mpython_get_hashmap(opath); 
    end

    fnstr = []; 

    files = dir(path); 
    for i = 1:numel(files)
        file = files(i); 
        if  ~isempty(regexp(file.name, '^\.', 'match'))
            continue
        end
        
        if file.isdir
            if ~isempty(regexp(file.name, '^@', 'match'))
                classname = strrep(file.name, '@', ''); 
                classpath = fullfile(path, file.name); 

                classfiles = [dir(fullfile(classpath, '*.m'))]; 
                haschanged = false; 
                for cf = classfiles' 
                    if strcmp(cf.name, 'Contents.m'), continue; end
                    [~, basename] = fileparts(cf.name);
                    haschanged = haschanged | ~mpython_check_hash(hashmap, [classname '_' basename], fullfile(cf.folder, cf.name)); 
                    if haschanged
                        break; 
                    end
                end
                if ~haschanged
                    classfiles = dir(fullfile(file.name, 'private', '*.m'));
                    for cf = classfiles' 
                        [~, basename] = fileparts(cf.name);
                        haschanged = haschanged | ~mpython_check_hash(hashmap, [classname '__' basename], fullfile(cf.folder, cf.name)); 
                    end
                end

                if haschanged
                    hdrstr = mpython_wrap_class(classname, classpath);
                    [~, hash] = mpython_check_hash(hashmap, [classname '_' classname], fullfile(classpath, [classname '.m']));
                    hashmap = mpython_update_hash(hashmap, [classname '_' classname], hash); 

                    [pystr, ~, innerhashmap] = mpython_wrap(classpath, opath, file.name, overwrite, templatedir, false, false, true, false, classname); 
                    pystr = [hdrstr pystr]; 
                    hashmap = mpython_merge_hashmaps(hashmap, innerhashmap);

                    try 
                        [str, ~, innerhashmap] = mpython_wrap(fullfile(classpath, 'private'), opath, file.name, overwrite, templatedir, false, false, true, true, classname); 
                        pystr = [pystr str]; 
                        hashmap = mpython_merge_hashmaps(hashmap, innerhashmap);
                    end

                    writelines(pystr, fullfile(opath, [classname '.py']));
                end

                initstr = [initstr 'from .' classname ' import ' classname newline]; 
                
            elseif ~isempty(regexp(file.name, '^+', 'match'))
                mpython_wrap(fullfile(path, file.name), opath, file.name, overwrite, templatedir, true, false, false, isprivate);
                initstr = [initstr 'import .' file.name newline]; 

            elseif isempty(regexp(fullfile(path, file.name), ['.*?_' PKGNAME], 'match'))
                [~, initstr_pr, innerhashmap] = mpython_wrap(fullfile(path, file.name), opath, ['__' file.name], overwrite, templatedir, false, false, isclass, isprivate | strcmp(file.name, 'private'), clsname);
                if isempty(initstr_pr)
                    continue
                elseif isprivate | strcmp(file.name, 'private')
                    hashmap = mpython_merge_hashmaps(hashmap, innerhashmap); 
                    initstr = [initstr initstr_pr]; 
                else
                    importname = strrep(file.name, '.', '_'); 
                    importname = strrep(importname, '-', '_'); 
                    initstr = [initstr 'from .' ['__' importname] ' import *' newline]; 
                end
            end
        else
            [~, basename, ext] = fileparts(file.name); 
            if strcmp(ext, '.m') 
                if isclass & strcmp(basename, clsname) 
                    continue % skip @cls/cls.m
                end
                if strcmp(basename, 'Contents')
                    continue % skip Contents.m
                end
                if isprivate
                    basename = ['_' basename];
                end
                basename = strrep(basename, '-', '_');
                basename = strrep(basename, '.', '_');

                [issame, hash, ignored] = mpython_check_hash(hashmap, basename, fullfile(path, file.name));
                if ~issame || isclass
                    fprintf('Processing %s\n', fullfile(path, file.name))
                    ignored = false; 
                    try 
                        pystr = mpython_wrap_function(fullfile(path, file.name), isclass, basename);
                        if isclass
                            fnstr = [fnstr, pystr]; 
                        else
                            writelines(pystr, fullfile(opath, [basename '.py']));
                        end 
                    catch 
                        err = lasterror;
                        warning(['Could not wrap file %s' filesep '%s\nDetails: %s'], path, file.name, err.message); 
                        ignored = true;
                    end

                    if isclass
                        hashmap = mpython_update_hash(hashmap, [clsname '_' basename], hash, ignored);
                    else
                        hashmap = mpython_update_hash(hashmap, basename, hash, ignored);
                    end
                end
                
                if ~isclass && ~ignored
                    initstr = [initstr 'from .' basename ' import ' basename newline]; 
                end
            end
        end
    end


    % if ispackage
    % create opath/dirname/dirname/__init__.py 
    if ~isclass && ~isprivate
        if numel(dir(opath)) == 2
            rmdir(opath);
        else
            mpython_save_hashmap(hashmap, opath); 
        end

        if ~isempty(initstr) 
            initstr = mpython_repl('init', 'imports', initstr); 
            writelines(initstr, fullfile(opath, '__init__.py'));
        end
    end    

    if istoplevel
        fprintf('Done!\n'); 
    end
end


function pystr = mpython_wrap_function(file, ismethod, pyfname)
    % Read function code
    str = fileread(file); 

    % Extract function signature
    rgx = '^function\s*(?<argout>\[?[\w,\s]+\]?\s*=\s*)?(?<fname>\w+)\s*(?<argin>\([\w,\s]*?\))?';
    
    fun = regexp(str, rgx,'names');
    if isempty(fun)
        error('No function in %s.', file); 
    end
    if nargin < 3
        pyfname = fun.fname;
    end

    % Check for output arguments
    nargoutstr = ', nargout=0'; 
    if isfield(fun, 'argout')
        fun.argout = strrep(fun.argout, '[', '');
        fun.argout = strrep(fun.argout, ']', '');            
        fun.argout = strrep(fun.argout, ' ', ''); 
        if ~isempty(fun.argout)
            nargoutstr = ''; 
        end
    end
    
    % Prepend self to methods arguments
    if ismethod
        selfstr  = 'self, ';
    else 
        selfstr = ''; 
    end
    
    % Fill in docstring
    docstring = mpython_repl('docstring', 'file', file);

    % Fill in function signature
    funsign   = mpython_repl('function_signature', ...
        'docstring', docstring, ...
        'fname', fun.fname, ...
        'pyfname', pyfname, ...
        'file', file, ...
        'nargout', nargoutstr, ...
        'self', selfstr); 

    if ismethod
        % Indent methods
        pystr = [newline mpython_indent(funsign, 4)]; 
    else 
        % Add import statement
        funhdr = mpython_repl('function_header'); 
        pystr = [
            funhdr ...
            newline ...
            newline ...
            funsign
        ];
    end
end

function pystr = mpython_wrap_class(classname, path)
    initfile = fullfile(path, [classname '.m']); 
    
    docstring    = mpython_repl('docstring', 'file', initfile); 
    class_header = mpython_repl('class_header', ...
        'classname', classname, ...
        'docstring', docstring ...
    );
    
    pystr = class_header; 
end


function mpython_create_wrapper(path)
    global TEMPLATES

    writelines(TEMPLATES.wrapper, fullfile(path, '__wrapper__.py'))
end

function mpython_create_setup(path)
    global TEMPLATES

    writelines(TEMPLATES.setup, fullfile(path, '..', 'setup.py'))
end

function repl = mpython_repl(attr, varargin)
    global TEMPLATES ROOTPATH

    sub = struct;
    args = struct(varargin{:}); 

    repl = TEMPLATES.(attr); 

    switch attr
        case 'docstring'

            doc = help(args.file); 
            doc = strrep(doc, newline, sprintf('  \n  '));

            sub.matlabhelp = doc; 
            
            rfilepath = strrep(args.file, [ROOTPATH filesep], ''); 
            sub.rfilepath = rfilepath; 
            
        otherwise 
            sub = args; 
    end 

    for fn = fieldnames(sub)'
        tag = ['<' fn{1} '>']; 
        str = sub.(fn{1}); 

        if strcmp(fn{1}, 'docstring')
            tok = regexp(repl, ['^(?<indent>\s+)' tag], 'names', ...
                'lineanchors'); 
            if ~isempty(tok)
                indent = regexprep(tok.indent, '\t', '    ');
                indent = length(indent); 
                str = mpython_indent(str, indent);
                tag = [tok.indent tag]; 
            end
        end
        
        repl = regexprep(repl, tag, str); 
    end
end

function str = mpython_indent(str, indent)
    str = regexprep(str, '^(.*)', [ repelem(' ', indent) '$1'], ...
        'lineanchors', 'dotexceptnewline');
end

% HASHMAP 
function hashmap = mpython_get_hashmap(path)
    file = fullfile(path, '.mpython_hashmap.csv'); 
    try
        hashfile = fileread(file);  
        tokens  = regexp(hashfile, '^(.*?),(.*?)$', 'tokens', 'lineanchors'); 
        tokens  = [tokens{:}]; 
        hashmap = struct(tokens{:}); 
    catch
        if exist(file, 'file')
            warning('Could not read hashmap in %s', file);
        end
        hashmap = struct; 
    end
end

function hashmap = mpython_merge_hashmaps(varargin)
    switch nargin
        case 1
            hashmap = varargin{1};
        case 2
            [x, y] = varargin{:}; 
            for fn = fieldnames(y)'
                try
                    x.(fn{1}) = y.(fn{1});
                    % left has priority
                end
            end
            hashmap = x; 
        otherwise
            x = varargin{1}; 
            y = mpython_merge_hashmaps(varargin{2:end}); 
            hashmap = mpython_merge_hashmaps(x, y); 
    end
end

function mpython_save_hashmap(hashmap, path)
    file = fullfile(path, '.mpython_hashmap.csv'); 
    filestr = []; 
    for fn = fieldnames(hashmap)'
        filestr = [filestr fn{1} ',' hashmap.(fn{1}) newline]; 
    end
    if ~isempty(filestr)
        writelines(filestr, file); 
    end
end

function [issame, hash, ignored] = mpython_check_hash(hashmap, basename, file)
    hash = char(mlreportgen.utils.hash(fileread(file))); 
    try 
        prevhash = hashmap.(['f_' basename]); 
    catch 
        issame = false; 
        ignored = false; 
        return 
    end
    split = strsplit(prevhash, ','); 
    issame = strcmp(split{1}, hash); 
    ignored = ~isempty(split{2});
end

function hashmap = mpython_update_hash(hashmap, basename, hash, ignored)
    if nargin < 4 || ~ignored
        ignored = ''; 
    else
        ignored = 'ignored';
    end
    hashmap.(['f_' basename]) = [hash ',' ignored]; 
end

function templates = mpython_load_templates(templatedir)
    global PKGNAME;

    files = {
        'wrapper.py'
        'init.py'
        'class_header.py'
        'function_header.py'
        'function_signature.py'
        'docstring.py'
        'setup.py'
    }; 

    [filepath,~,~] = fileparts(mfilename("fullpath")); 
    roottemplatedir = fullfile(filepath, 'templates'); 

    if isempty(templatedir)
        templatedir = roottemplatedir; 
    else
        templatedir = getfield(dir(templatedir), 'folder'); 
    end

    templatefiles = cellfun(@(f) fullfile(templatedir, f), files, 'UniformOutput',false); 
    roottemplatefiles = cellfun(@(f) fullfile(roottemplatedir, f), files, 'UniformOutput',false); 

    fns = strrep(files, '.py', ''); 

    fprintf('Loading templates...\n')

    templates = struct; 
    for i = 1:numel(files)
        try
            f = templatefiles{i}; 
            content = fileread(f); 
        catch
            f = roottemplatefiles{i};
            content = fileread(f); 
        end
        fprintf('"%s": %s\n', fns{i}, f);
        templates.(fns{i}) = strrep(content, '<pkgname>', PKGNAME); 
    end
end