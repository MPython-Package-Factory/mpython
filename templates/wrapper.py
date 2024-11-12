try:
	from <pkgname>._<pkgname> import initialize
except ImportError as e:
	import os
	installer_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 
        '_<pkgname>', 
        'resources',
        'RuntimeInstaller.install')

	print("Failed to import, install Matlab Runtime and setup library path. ")
	print(f"Matlab Runtime installer can be found in: {installer_path}")
	raise e
import warnings
import numpy as np
import matlab

_matlab_numpy_types = {
    matlab.double: np.float64,
    matlab.single: np.float32,
    matlab.logical: np.bool,
    matlab.uint64: np.uint64,
    matlab.uint32: np.uint32,
    matlab.uint16: np.uint16,
    matlab.uint8 : np.uint8,
    matlab.int64: np.int64,
    matlab.int32: np.int32,
    matlab.int16: np.int16,
    matlab.int8 : np.int8,
}


class MatlabClassWrapper:
    _subclasses = dict()

    def _as_matlab_object(self):
        return self._objdict

    def __init_subclass__(cls):
        super().__init_subclass__()
        MatlabClassWrapper._subclasses[cls.__name__] = cls

    def __new__(cls, *args, _objdict=None, **kwargs):
        if _objdict is None:
            if cls.__name__ in MatlabClassWrapper._subclasses.keys():
                obj = Runtime.call(cls.__name__, *args, **kwargs)
            else:
                obj = super().__new__(cls)
        else:
            obj = super().__new__(cls)
            obj._objdict = _objdict
        return obj

    def __init_subclass__(cls):
        super().__init_subclass__()
        if hasattr(cls, 'subsref'):
            cls.__getitem__ = MatlabClassWrapper.__getitem
            cls.__call__    = MatlabClassWrapper.__call

        if hasattr(cls, 'subsasgn'):
            cls.__setitem__ = MatlabClassWrapper.__setitem

        MatlabClassWrapper._subclasses[cls.__name__] = cls

    def __getattr(self, key):
        try:
            return self.subsref({'type': '.', 'subs': key})
        except:
            raise AttributeError(key)

    def __getitem(self, ind):
        index = self._process_index(ind)

        try:
            return self.subsref({'type': '()', 'subs': index})
        except:
            try:
                return self.subsref({'type': '{}', 'subs': index})
            except:
                raise IndexError(index)

    def __setitem(self, ind, value):
        index = self._process_index(ind)

        try:
            return self.subsasgn({'type': '()', 'subs': index}, value)
        except:
            try:
                return self.subsasgn({'type': '{}', 'subs': index}, value)
            except:
                raise IndexError(index)

    def __call(self, *index):
        index = self._process_index(index)
        try:
            return self.subsref({'type': '{}', 'subs': index})
        except:
            raise IndexError(index)

    def _process_index(self, ind, k=1, n=1):
        try:
            return [self._process_index(i, k+1, len(ind))
                    for k, i in enumerate(ind)]
        except TypeError:
            pass

        if not hasattr(self, '__endfn'):
            self.__endfn = Runtime.call('str2func', 'end')

        end = lambda: Runtime.call(self.__endfn, self._as_matlab_object(), k, n)

        if isinstance(ind, int):
            if ind >= 0:
                index = ind + 1
            elif ind == -1:
                index = end()
            else:
                index = end() + ind - 1
        elif isinstance(ind, slice):
            if ind.start is None and ind.stop is None and ind.step is None:
                index = ':'
            else:
                if ind.start is None:
                    start = 1
                elif ind.start < 0:
                    start = end() + ind.start
                else:
                    start = ind.start + 1

                if ind.stop is None:
                    stop = end()
                elif ind.stop < 0:
                    stop = end() + ind.stop
                else:
                    stop = ind.stop + 1

                if ind.step is None:
                    step = 1
                else:
                    step = ind.step

                min_ = min(start, stop)
                max_ = max(start, stop)
                if step > 0:
                    index = np.arange(min_, max_, step)
                else:
                    index = np.arange(max_, min_, step)
        else:
            index = ind


        return index


class Runtime:
    _instance = None
    verbose = True

    @staticmethod
    def instance():
        if Runtime._instance is None:
            if Runtime.verbose:
                print('Initializing Matlab Runtime...')
            Runtime._instance = initialize()
        return Runtime._instance

    @staticmethod
    def call(fn, *args, **kwargs):
        [args, kwargs] = Runtime._process_argin(*args, **kwargs)
        res = Runtime.instance().mpython_endpoint(fn, *args, **kwargs)
        return Runtime._process_argout(res)

    @staticmethod
    def _cast_argin(arg):
        if isinstance(arg, MatlabClassWrapper):
            arg = arg._as_matlab_object()
        if isinstance(arg, dict):
            _, arg = Runtime._process_argin(**arg)
        elif isinstance(arg, (tuple, dict, list, set)):
            arg, _ = Runtime._process_argin(*arg)
        return arg

    @staticmethod
    def _process_argin(*args, **kwargs):
        args = tuple(map(Runtime._cast_argin, args))
        kwargs = dict(zip(
            kwargs.keys(),
            map(Runtime._cast_argin, kwargs.values())))

        return args, kwargs

    @staticmethod
    def _process_argout(res):
        out = res
        if type(res) in _matlab_numpy_types.keys():
            try:
                out = np.asarray(res, dtype=_matlab_numpy_types[type(res)])
            except:
                pass
        elif isinstance(res, tuple):
            out = tuple(Runtime._process_argout(r) for r in res)
        elif isinstance(res, list):
            out = list(Runtime._process_argout(r) for r in res)
        elif isinstance(res, dict):
            res = dict(zip(res.keys(), map(Runtime._process_argout, res.values())))
            if 'type__' in res.keys():
                if res['type__'] == 'object':
                    if res['class__'] in MatlabClassWrapper._subclasses.keys():
                        out = MatlabClassWrapper._subclasses[res['class__']](_objdict=res)
                    else:
                        warnings.warn(f'Unknown Matlab class type: {res["type__"]}')
                        out = MatlabClassWrapper(_objdict=res)
                else:
                    out = res
            else:
                out = Struct(**res)
        return out


class Struct(dict):
    """emulates struct with a dot.notation access to dictionary attributes"""
    __getattr__ = dict.__getitem__
    __setattr__ = dict.__setitem__
    __delattr__ = dict.__delitem__


class Cell(list):
    """emulates matlab's cell"""
    def __init__(self, m, n):
        super().__init__([[] for j in range(n)] for i in range(m))

    def __getitem__(self, index):
        if isinstance(index, tuple):
            i, j = index
            return self[i][j]
        else:
            return super().__getitem__(index)

    def __setitem__(self, index, value):
        if isinstance(index, tuple):
            i, j = index
            xi = self[i]
            xi[j] = value
            self[i] = xi
        else:
            super().__setitem__(index, value)
