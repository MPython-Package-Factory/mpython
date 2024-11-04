function [varargout] = mpython_endpoint(F, varargin)
% FUNCTION [varargout] = mpython_endpoint(F, varargin)
%   Calls a Matlab function, converting arguments in/out from/to
%   types compatible with Python. 
% 
% This function is the endpoint used to call any function from Python. Its
% role is to convert arguments in and out into objects that are supported
% by the Matlab Runtime Engine in Python. 
    varargout = cell(1, nargout); 

    if nargin > 0
        [varargin{:}]  = check_argin(varargin{:});
    end
    
    if strcmp(F, 'display') && nargout == 1 
        varargout{1} = evalc('display(varargin{:})'); 
    else
        [varargout{:}] = feval(F, varargin{:}); 
    end

    if nargout > 0
        [varargout{:}] = check_argout(varargout{:}); 
    end
end

function varargout = check_argin(varargin)
    % Converts arguments from Matlab Runtime compatible types to generic
    % Matlab types. 

    varargout = cell(1, nargout); 

    for i = 1:numel(varargout)
        S = varargin{i};

        % Dive in cell and struct
        if iscell(S) 
            for j = 1:numel(S)
                S{i} = check_argin(S{i});
            end
        elseif isstruct(S)
            fn = fieldnames(S); 
            for j = 1:numel(fn)
                S.(fn{j}) = check_argin(S.(fn{j}));
            end
        end 

        % Convert to unsupported MATLAB Types
        % These MATLAB types are not supported in Python.
        if isstruct(S) & isfield(S, 'type__') 

            % 1. Multidimensional char or cell arrays
            if strcmp(S.type__, 'cell')
                s = reshape(S.data__, S.size__);  
            
            % 2. Sparse arrays
            elseif strcmp(S.type__, 'sparse')
                s = sparse(S.data__); 

            % 3. struct arrays
            elseif strcmp(S.type__, 'structarray')
                s = reshape([S.data__{:}], S.size__);

            % 3. struct arrays
            elseif strcmp(S.type__, 'emptystruct')
                s = struct([]);

            % 4. MATLAB objects
            elseif strcmp(S.type__, 'object')
                try 
                    s = feval(S.class__, S.data__); 
                catch
                    s = feval(S.class__); 
                    for f = fieldnames(s)'
                        try 
                            s.(f) = S.data__.(f);
                        end
                    end
                end
            end
        elseif isnumeric(S)
            s = double(S); 
        else
            s = S; 
        end
    
        varargout{i} = s; 
    end
end

function varargout = check_argout(varargin)
    varargout = cell(1, nargout); 

    for i = 1:nargout
        S = varargin{i};

        % Unsupported MATLAB Types
        % These MATLAB types are not supported in Python.
        
        % 1. Multidimensional char or cell arrays
        if iscell(S)  & (numel(S) ~= length(S))
            s = struct();
            s.type__ = 'cell';
            s.size__ = size(S); 
            s.data__ = reshape(S, 1, []); 

        elseif ischar(S)  & (numel(S) ~= length(S))
            s = struct();
            s.type__ = 'char';
            s.size__ = size(S); 
            s.data__ = cellstr(S); 

        % 2. Sparse arrays
        elseif issparse(S)
            s = struct('data__', full(S),  'type__', 'sparse'); 

        % 3. struct arrays
        elseif (isstruct(S) & numel(S) > 1)
            s = struct();
            s.type__ = 'structarray';
            s.size__ = size(S); 
            s.data__ = arrayfun(@(o) o, S, 'UniformOutput', false); 

        % 3. struct arrays
        elseif (isstruct(S) & numel(S) == 0)
            s = struct; 
            s.type__ = 'emptystruct'; 

        % 4. MATLAB objects
        elseif isobject(S) && ~isstring(S) && ~isdatetime(S)
            s = struct();
            s.type__ = 'object';
            s.class__ = class(S); 
            s.data__ = struct(S); 
        
        else 
            s = S; 
        end
        
        switch class(s)
            case 'cell'
                assert(numel(s) == length(s)); 
            case 'char'
                assert(numel(s) == length(s)); 
            case 'struct'
                assert(isscalar(s)); 
            case 'double'
                assert(~issparse(s));
                assert(isscalar(s) || isreal(s));
            case 'int'
                assert(~issparse(s)); 
                assert(isscalar(s) || isreal(s));
            case 'uint32'
                assert(~issparse(s)); 
                assert(isscalar(s) || isreal(s));
            case 'logical'
            case 'string'
                assert(isscalar(s))
            case 'datetime'
                assert(isscalar(s))
            otherwise
                fprintf('%s\n', class(s))
        end
        % 5. categorical types
        % 6. containers.Map types
        % 7. matlab.metadata.Class (py.class)    
        
        % dive in
        if iscell(s) 
            for j = 1:numel(s)
                if ~isempty(s{i})
                    s{i} = check_argout(s{i});
                end
            end
        elseif isstruct(s) 
            fn = fieldnames(s);
            for j = 1:numel(fn)
                o = check_argout(s.(fn{j}));
                s.(fn{j}) = o; 
            end
        end 

        varargout{i} = s; 
    end
end
