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
        try
            [varargout{:}] = feval(F, varargin{:}); 
        catch E
            if nargout == 1
                % Prepare to return None
                varargout{1} = struct('type__', 'none');
                switch E.identifier
                    case {'MATLAB:TooManyOutputs'}
                        % This error is raised before F is even evaluated
                        % -> we need to rerun it without output
                        feval(F, varargin{:});
                    case {'MATLAB:unassignedOutputs'}
                        % This error is raised after F is evaluated
                        % -> no need to rerun it
                    otherwise
                        rethrow(E);
                end
            else
                rethrow(E);
            end
        end
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
                S{j} = check_argin(S{j});
            end
        elseif isstruct(S)
            if isscalar(S) % Scalar structure
                fn = fieldnames(S); 
                for j = 1:numel(fn)
                    S.(fn{j}) = check_argin(S.(fn{j}));
                end
            else
                for j = 1:numel(S)
                    S(j) = check_argin(S(j));
                end
            end
        end 

        % Convert to unsupported MATLAB Types
        % These MATLAB types are not supported in Python.
        if isstruct(S) & isfield(S, 'type__') 

            % 1. Multidimensional char or cell arrays
            if strcmp(S.type__, 'cell')
                if isempty(S.size__)
                    S.size__ = [1, 0];
                elseif isscalar(S.size__)
                    S.size__ = [1, S.size__];
                end
                s = reshape(S.data__, S.size__);  
            
            % 2. Sparse arrays
            elseif strcmp(S.type__, 'sparse')
                if isempty(S.size__)
                    S.size__ = [1, 0];
                elseif isscalar(S.size__)
                    S.size__ = [1, S.size__];
                end
                s = sparse(S.indices__(:,1), S.indices__(:,2), S.values__, S.size__(1), S.size__(2));

            % 3. struct arrays
            elseif strcmp(S.type__, 'structarray')
                if isempty(S.size__)
                    S.size__ = [1, 0];
                elseif isscalar(S.size__)
                    S.size__ = [1, S.size__];
                end
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
                        catch
                            % ignore
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
        % 
        %    Check for non-column cell arrays, escape infinite recursion
        % after conversion to shape (1,n)
        if iscell(S) & (numel(S) ~= size(S,2)) 
            s = struct();
            s.type__ = 'cell';
            s.size__ = size(S); 
            s.data__ = reshape(S, 1, []); 

        elseif ischar(S)  & (numel(S) ~= length(S))
            s = struct();
            s.type__ = 'char';
            s.size__ = size(S); 
            s.data__ = reshape(...
                cellstr(S), 1, []); 

        % 2. Sparse arrays
        elseif issparse(S)
            s = struct(); 
            [ii,jj,v] = find(S);
            s.type__ = 'sparse';
            s.size__ = size(S);
            s.indices__ = [ii,jj];
            s.values__ = v;

        % 3. struct arrays
        elseif (isstruct(S) & numel(S) > 1)
            s = struct();
            s.type__ = 'structarray';
            s.size__ = size(S); 
            s.data__ = reshape(...
                arrayfun(@(o) o, S, 'UniformOutput', false), 1, []); 

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
            case 'logical'
            case 'string'
                assert(isscalar(s));
            case 'datetime'
                assert(isscalar(s));
            otherwise
                if isnumeric(s)
                    assert(~issparse(s)); 
                    assert(isscalar(s) || isreal(s));
                end
        end
        % 5. categorical types
        % 6. containers.Map types
        % 7. matlab.metadata.Class (py.class)    
        
        % dive in
        if iscell(s) 
            for j = 1:numel(s)
                if ~isempty(s{j})
                    s{j} = check_argout(s{j});
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
