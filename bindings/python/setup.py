"""Setup script for Pyjamaz Python bindings."""

from setuptools import setup, find_packages
from pathlib import Path

# Read README
readme_file = Path(__file__).parent / "README.md"
long_description = readme_file.read_text() if readme_file.exists() else ""

setup(
    name="pyjamaz",
    version="1.0.0",
    author="Your Name",
    author_email="your.email@example.com",
    description="High-performance image optimizer with perceptual quality guarantees",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/yourusername/pyjamaz",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Multimedia :: Graphics :: Graphics Conversion",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
    ],
    python_requires=">=3.8",
    install_requires=[
        # No dependencies - uses ctypes (stdlib)
    ],
    extras_require={
        "dev": [
            "pytest>=7.0",
            "pytest-cov>=4.0",
            "black>=23.0",
            "mypy>=1.0",
            "ruff>=0.1",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)
