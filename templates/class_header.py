from <pkgname>.__wrapper__ import Runtime, MatlabClassWrapper


class <classname>(MatlabClassWrapper):
    def __init__(self, *args, _objdict=None, **kwargs):
        <docstring>
        if _objdict is None:
            _objdict = Runtime.call("<classname>", *args, **kwargs)
            
        super().__init__(_objdict)
