function mpython_compile(ipath, opath, pkgname, toolboxes, includes)
    if nargin < 3
        [~, pkgname] = fileparts(ipath);
    end
    pkgname = strrep(pkgname, '.', '_'); 
    pkgname = strrep(pkgname, '-', '_'); 
    runtime_installer_name = 'RuntimeInstaller';


    if nargin < 4
        toolboxes = {};
    end
    Nargs = {}; 
    if ~isempty(toolboxes)
        Nargs = {'-N'}; 
        for i = 1:numel(toolboxes)
           Nargs = [Nargs, {'-p' toolboxes{i}}];
        end
    end
    
    if nargin < 5
        pathargs = {'-a', getfield(dir(ipath), 'folder')};
    else
        pathargs = {}; 
        for i = 1:numel(includes)
            files = dir(fullfile(ipath, '**', includes{i})); 
            folders = unique({files.folder}); 
            for j = 1:numel(folders)
                pathargs = [pathargs, {'-a'} {fullfile(folders{j}, includes{i})}];
            end
        end
    end

    if ~exist(opath, 'dir')
        mkdir(opath); 
    end
    try
        rmdir(builddir)
    end
    
    opath = getfield(dir(opath), 'folder'); 
    builddir = fullfile(opath, 'build');

    mcc('-v',...
        '-W',['python:_' pkgname],...
        '-G', '-K', '-X', ...
        '-d', builddir,...
        Nargs{:}, ...
        pathargs{:}, ...
        'mpython_endpoint'... 
    );
    
    innerpath = fullfile(opath, pkgname, ['_' pkgname]);
    try
        rmdir(innerpath)
    end
    copyfile(fullfile(builddir, ['_' pkgname], '*'), fullfile(innerpath), "f"); 
    
end
