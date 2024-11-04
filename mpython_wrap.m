function [fnstr, initstr, hashmap] = mpython_wrap(path, opath, dirname, ispackage, istoplevel, isclass, isprivate, clsname)
    global PKGNAME; 
    if nargin < 4
        ispackage = true;
    end
    if nargin < 5
        istoplevel = ispackage;
    end
    if nargin < 6
        isclass = false; 
    end
    if nargin < 7
        isprivate = false; 
    end
    if nargin < 8
        clsname = '';
    end

    dirname = strrep(dirname, '-', '_');
    dirname = strrep(dirname, '.', '_');

    % top level package 
    if istoplevel
        % create opath/
        if ~exist(opath, 'dir')
            mkdir(opath)
        end
        % create opath/setup.py

        clear global PKGNAME ;
        global PKGNAME; 
        PKGNAME = dirname; 

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
        mpython_create_mwraputil(opath, dirname);
    end

    % get hashmap
    hashmap = mpython_get_hashmap(opath); 


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

                    [pystr, ~, innerhashmap] = mpython_wrap(classpath, opath, file.name, false, false, true, false, classname); 
                    pystr = [hdrstr pystr]; 
                    
                    hashmap = mpython_merge_hashmaps(hashmap, innerhashmap); 
                    writelines(pystr, fullfile(opath, [classname '.py']));
                end

                initstr = [initstr 'from .' classname ' import ' classname newline]; 
                
            elseif ~isempty(regexp(file.name, '^+', 'match'))
                mpython_wrap(fullfile(path, file.name), opath, file.name, true, false, false, isprivate);
                initstr = [initstr 'import .' file.name newline]; 

            elseif isempty(regexp(fullfile(path, file.name), ['.*?_' PKGNAME], 'match'))
                [~, initstr_pr, innerhashmap] = mpython_wrap(fullfile(path, file.name), opath, ['__' file.name], false, false, isclass, isprivate | strcmp(file.name, 'private'), clsname);
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
                        warning(['Could not wrap file %s' filesep '%s'], path, file.name); 
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
            writelines(initstr, fullfile(opath, '__init__.py'));
        end
    end    

    if istoplevel
        fprintf('Done!\n'); 
    end
end


function pystr = mpython_wrap_function(file, ismethod, pyfname)
    if ismethod
        if strcmp(pyfname, '__init__')
            template = [...
              '  def __init__(self, *args, _objdict=None, **kwargs):' newline...
              '    """<doc>' newline newline...
              '  [Link to the Matlab implementation.](https://github.com/spm/spm/blob/main/<file>)' newline...
              '    """' newline newline...
              '    if _objdict is None:' newline ...
              '      _objdict = Runtime.call("<fname>", *args, **kwargs)' newline...
              '    super().__init__(_objdict)' newline newline...
            ];
        else
            template = [...
              '  def <pyfname>(self, *args, **kwargs):' newline...
              '    """<doc>' newline newline...
              '  [Link to the Matlab implementation.](https://github.com/spm/spm/blob/main/<file>)' newline...
              '    """' newline newline...
              '    return Runtime.call("<fname>", self._as_matlab_object(), *args, **kwargs)' newline newline...
            ];
        end
        if strcmp(pyfname, 'display') % map display onto Python __repr__
            template = [template... 
              '  __repr__ = display # Use display to represent objects' ...
              newline newline...
            ];
        end
    else 
        global PKGNAME; 
        template = [...
          'from ' PKGNAME '.__wrapper__ import Runtime' newline newline newline...
          'def <pyfname>(*args, **kwargs):' newline...
          '  """<doc>' newline newline...
          '  [Link to the Matlab implementation.](https://github.com/spm/spm/blob/main/<file>)' newline...
          '  """' newline newline...
          '  return Runtime.call("<fname>", *args, **kwargs<nargout>)' newline...
        ];
    end
    
    py_reserved = {'False', 'None', 'True', 'and', 'as', 'assert', 'async', ...
        'await', 'break', 'class', 'continue', 'def', 'del', 'elif', 'else', ...
        'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', ...
        'is', 'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', ...
        'try', 'while', 'with', 'yield'};
    
    swapcase = @(c)  char(bitxor(double(c), 32));
    
    str = fileread(file); 
    % rgx = '^function\s*(\[?(?<argout>[\w,\s]+)\]?\s*?=\s*?)?(?<fname>\w+)\s*?(\(\s*(?<argin>.*?)?\s*\))?';
    rgx = '^function\s*(?<argout>\[?[\w,\s]+\]?\s*=\s*)?(?<fname>\w+)\s*(?<argin>\([\w,\s]*?\))?';

    fun = []; 
    fun = regexp(str, rgx,'names');
    if isempty(fun)
        error('No function in %s.', file); 
    end

    nargoutstr = ', nargout=0'; 
    if isfield(fun, 'argout')
        fun.argout = strrep(fun.argout, '[', '');
        fun.argout = strrep(fun.argout, ']', '');            
        fun.argout = strrep(fun.argout, ' ', ''); 
        if ~isempty(fun.argout)
            nargoutstr = ''; 
        end
    end

    doc = help(file); 
    doc = strrep(doc, newline, sprintf('  \n  '));

    pystr = template; 
    pystr = strrep(pystr, '<doc>', doc); 
    pystr = strrep(pystr, '<fname>', fun.fname); 
    pystr = strrep(pystr, '<file>', strrep(file,'spm/','')); 
    try
        pystr = strrep(pystr, '<pyfname>', pyfname); 
    catch 
        pystr = strrep(pystr, '<pyfname>', fun.fname); 
    end
    pystr = strrep(pystr, '<nargout>', nargoutstr); 
end

function pystr = mpython_wrap_class(classname, path)
    global PKGNAME; 
    template = [...
      'from ' PKGNAME '.__wrapper__ import Runtime, MatlabClassWrapper' newline newline newline...
      'class ' classname '(MatlabClassWrapper):' newline ...
    ];
    
    initfile = fullfile(path, [classname '.m']); 
    pystr =  mpython_wrap_function(initfile, true, '__init__');
    pystr = [template, pystr]; 
end


function mpython_create_mwraputil(path, dirname)
    [filepath,~,~] = fileparts(mfilename('fullpath')); 
    pystr = readlines(fullfile(filepath, 'payload', '__wrapper__.py')); 
    pystr = strrep(pystr, '<pkgname>', dirname); 
    writelines(pystr, fullfile(path, '__wrapper__.py'))
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