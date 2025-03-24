from setuptools import setup, find_packages

# Read the contents of your README file for the long description
with open("README.md", "r") as fh:
    long_description = fh.read()

# Setup configuration
setup(
    name='<pkgname>',
    version='0.1.0', 
    author='John Doe',
    author_email='', 
    description='Python bindings for the <pkgname> Matlab package.',
    long_description=long_description,
    long_description_content_type='text/markdown',
    packages=find_packages(),  
    include_package_data=True, 
    package_data={
        '<pkgname>': [
            '_<pkgname>/_<pkgname>.ctf', 
            '_<pkgname>/resources/RuntimeInstaller.install'
        ], 
    },
    classifiers=[
        'Programming Language :: Python :: 3',
        'License :: OSI Approved :: GPL2', 
        'Operating System :: OS Independent',
    ],
    python_requires='>=3.6', 
    install_requires=[
        'mpython-core'
    ] 
)
