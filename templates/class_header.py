from <pkgname>.__wrapper__ import Runtime, MatlabClassWrapper


class <classname>(MatlabClassWrapper):
    def __init__(self, *args, _objdict=None, **kwargs):
        <docstring>
        super().__init__(_objdict)
