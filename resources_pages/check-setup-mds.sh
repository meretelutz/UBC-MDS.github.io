#!/usr/bin/env bash
# Checks that the correct version of all system programs and R & Python packages
# which are needed for the start of the MDS program are correctly installed.

# 0. Help message and OS info
echo ''
echo "# MDS setup check 0.0.2" | tee check-setup-mds.log
echo '' | tee -a check-setup-mds.log
echo 'If a program or package is marked as MISSING,'
echo 'this means that you are missing the required version of that program or package.'
echo 'Either it is not installed at all or the wrong version is installed.'
echo 'The required version is indicated with a number and an asterisk (*),'
echo 'e.g. 4.* means that all versions starting with 4 are accepted (4.0.1, 4.2.5, etc).'
echo ''
echo 'You can run the following commands to find out which version'
echo 'of a program or package is installed (if any):'
echo '```'
echo 'name_of_program --version  # For system programs'
echo 'conda list  # For Python packages'
echo 'R -q -e "installed.packages()[,c('Package', 'Version')]"  # For R packages'
echo '```'
echo ''
echo 'Checking program and package versions...'
echo '## Operating system' >> check-setup-mds.log
if [[ "$(uname)" == 'Linux' ]]; then
    sys_info=$(hostnamectl)
    grep "Operating" <<< $sys_info | sed 's/^[[:blank:]]*//' >> check-setup-mds.log
    grep "Architecture" <<< $sys_info | sed 's/^[[:blank:]]*//;s/:/:    /' >> check-setup-mds.log
    grep "Kernel" <<< $sys_info | sed 's/^[[:blank:]]*//;s/:/:          /' >> check-setup-mds.log
elif [[ "$(uname)" == 'Darwin' ]]; then
    sw_vers >> check-setup-mds.log
elif [[ "$OSTYPE" == 'msys' ]]; then
    echo $(wmic os get caption) >> check-setup-mds.log
    echo " $(grep bit <<< $(wmic os get osarchitecture))" >> check-setup-mds.log
    echo $(wmic os get version) >> check-setup-mds.log
else
    echo "Operating system verison could not be detected." >> check-setup-mds.log
fi
echo '' >> check-setup-mds.log

# 1. System programs
# Tries to run system programs and if successful greps their version string
# Currently marks both uninstalled and wrong verion number as MISSING
echo "## System programs" >> check-setup-mds.log

# There is an esoteric case for .app programs on macOS where `--version` does not work.
# Also, not all programs are added to path,
# so easier to test the location of the executable than having students add it to PATH.
if [[ "$(uname)" == 'Darwin' ]]; then
    # psql is not added to path by default
    if ! [ -x "$(command -v /Library/PostgreSQL/12/bin/psql)" ]; then
        echo "MISSING   postgreSQL 12.*" >> check-setup-mds.log
    else
        echo "OK        "$(/Library/PostgreSQL/12/bin/psql --version) >> check-setup-mds.log
    fi

    # rstudio is installed as an .app
    if ! $(grep -iq "= \"1.*" <<< "$(mdls -name kMDItemVersion /Applications/RStudio.app)"); then
        echo "MISSING   rstudio 1.*" >> check-setup-mds.log
    else
        # This is what is needed instead of --version
        installed_version_tmp=$(grep -io "= \"1.*" <<< "$(mdls -name kMDItemVersion /Applications/RStudio.app)")
        # Tidy strangely formatted version number
        installed_version=$(sed "s/= //;s/\"//g" <<< "$installed_version_tmp")
        echo "OK        "rstudio $installed_version >> check-setup-mds.log
    fi

    # Remove rstudio and psql from the programs to be tested using the normal --version test
    sys_progs=(R=4.* python=3.* conda=4.* bash=4.* git=2.* latex=3.* tlmgr=5.* docker=19.* code=1.*)
else
    # For Linux and Windows, test all packages the same way since there are no special cases
    sys_progs=(psql=12.* rstudio=1.* R=4.* python=3.* conda=4.* bash=4.* git=2.* latex=3.* tlmgr=5.* docker=19.* code=1.*)
    # Note that the single equal sign syntax is what we have in the install
    # instruction for conda, so I am using it for Python packagees so that we
    # can just paste in the same syntax as for the conda installations
    # instructions. Here, I use the same single `=` for the system packages
    # (and later for the R packages) for consistency.
fi

for sys_prog in ${sys_progs[@]}; do
    sys_prog_no_version=$(sed "s/=.*//" <<< "$sys_prog")
    regex_version=$(sed "s/.*=//" <<< "$sys_prog")
    # Check if the command exists and is is executable
    if ! [ -x "$(command -v $sys_prog_no_version)" ]; then
        # If the executable does not exist
        echo "MISSING   $sys_prog" >> check-setup-mds.log
    else
        # Check if the version regex string matches the installed version
        # Use `head` because `R --version` prints an essay...
        # Unfortunately (and inexplicably) R on windows and Python2 on macOS prints version info to stderr instead of stdout
        # Therefore I use the `&>` redirect of both streams, I don't like chopping of stderr with `head` like this,
        # but we should be able to tell if something is wrong from the first line and troubleshoot from there
        if ! $(grep -iq "$regex_version" <<< "$($sys_prog_no_version --version &> >(head -1))"); then
            # If the version is wrong
            echo "MISSING   $sys_prog" >> check-setup-mds.log
        else
            # Since programs like rstudio and vscode don't print the program name with `--version`,
            # we need one extra step before logging
            installed_version=$(grep -io "$regex_version" <<< "$($sys_prog_no_version --version &> >(head -1))")
            echo "OK        "$sys_prog_no_version $installed_version >> check-setup-mds.log
        fi
    fi
done

# 2. Python packages
# Greps the `conda list` output for correct version numbers
# Currently marks both uninstalled and wrong verion number as MISSING
echo "" >> check-setup-mds.log
echo "## Python packages" >> check-setup-mds.log
if ! [ -x "$(command -v conda)" ]; then  # Check that conda exists as an executable program
    echo "Please install 'conda' to check Python package versions." >> check-setup-mds.log
    echo "If 'conda' is installed already, make sure to run 'conda init'" >> check-setup-mds.log
    echo "if this was not chosen during the installation." >> check-setup-mds.log
    echo "In order to do this after the installation process," >> check-setup-mds.log
    echo "first run 'source <path to conda>/bin/activate' and then run 'conda init'." >> check-setup-mds.log
else
    py_pkgs=(jupyterlab=2 numpy=1 pandas=1 flake8=3 black=19 nodejs=10 jupytext=1 jupyterlab-git=0)
    # installed_py_pkgs=$(pip freeze)
    installed_py_pkgs=$(conda list | tail -n +4 | tr -s " " "=" | cut -d "=" -f -2)
    for py_pkg in ${py_pkgs[@]}; do
        # py_pkg=$(sed "s/=/==/" <<< "$py_pkg")
        if ! $(grep -iq "$py_pkg" <<< $installed_py_pkgs); then
            echo "MISSING   ${py_pkg}.*" >> check-setup-mds.log
        else
            # Match the package name up until the first whitespace to get regexed versions
            # without getting all following packages contained in the string of all pacakges
            echo "OK        $(grep -io "${py_pkg}\S*" <<< $installed_py_pkgs)" >> check-setup-mds.log
        fi
    done
fi

# jupyterlab PDF generation
if ! [ -x "$(command -v jupyter)" ]; then  # Check that jupyter exists as an executable program
    echo "Please install 'jupyterlab' before testing PDF generation." >> check-setup-mds.log
else
    # Create an empty json-compatible notebook file for testing
    echo '{
     "cells": [
      {
       "cell_type": "code",
       "execution_count": null,
       "metadata": {},
       "outputs": [],
       "source": []
      }
     ],
     "metadata": {
      "kernelspec": {
       "display_name": "",
       "name": ""
      },
      "language_info": {
       "name": ""
      }
     },
     "nbformat": 4,
     "nbformat_minor": 4
    }' > mds-nbconvert-pdf-test.ipynb
    if ! jupyter nbconvert mds-nbconvert-pdf-test.ipynb --to pdf &> /dev/null; then
        echo 'MISSING   jupyterlab PDF-generation failed. Check that latex and jupyterlab are marked OK above.' >> check-setup-mds.log
    else
        echo 'OK        jupyterlab PDF-generation was successful.' >> check-setup-mds.log
    fi
    rm mds-nbconvert-pdf-test.ipynb
fi

# 3. R packages
# Format R package output similar to above for python and grep for correct version numbers
# Currently marks both uninstalled and wrong verion number as MISSING
echo "" >> check-setup-mds.log
echo "## R packages" >> check-setup-mds.log
if ! [ -x "$(command -v R)" ]; then  # Check that R exists as an executable program
    echo "Please install 'R' to check R package versions." >> check-setup-mds.log
else
    r_pkgs=(tidyverse=1 blogdown=0 xaringan=0 renv=0 IRkernel=1 tinytex=0)
    installed_r_pkgs=$(R -q -e "print(format(as.data.frame(installed.packages()[,c('Package', 'Version')]), justify='left'), row.names=FALSE)" | grep -v "^>" | tail -n +2 | sed 's/^ //;s/ *$//' | tr -s ' ' '=')
    for r_pkg in ${r_pkgs[@]}; do
        if ! $(grep -iq "$r_pkg" <<< $installed_r_pkgs); then
            echo "MISSING   $r_pkg.*" >> check-setup-mds.log
        else
            # Match the package name up until the first whitespace to get regexed versions
            # without getting all following packages contained in the string of all pacakges
            echo "OK        $(grep -io "${r_pkg}\S*" <<< $installed_r_pkgs)" >> check-setup-mds.log
        fi
    done
fi

# rmarkdown PDF generation
if ! [ -x "$(command -v R)" ]; then  # Check that R exists as an executable program
    echo "Please install 'R' before testing PDF generation." >> check-setup-mds.log
else
    # Create an empty Rmd-file for testing
    touch mds-knit-pdf-test.Rmd
    if ! Rscript -e "rmarkdown::render('mds-knit-pdf-test.Rmd', output_format = 'pdf_document')" &> /dev/null; then
        echo "MISSING   rmarkdown PDF-generation failed. Check that latex and rmarkdown are marked OK above." >> check-setup-mds.log
    else
        echo 'OK        rmarkdown PDF-generation was successful.' >> check-setup-mds.log
    fi
    rm mds-knit-pdf-test.Rmd
fi

# 4. Ouput the saved file to stdout
# I am intentionally showing the entire output in the end,
# instead of progressively with `tee` throughout
# so that students have time to read the help message in the beginning.
tail -n +2 check-setup-mds.log  # `tail` to skip rows already echoed to stdout
