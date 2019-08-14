#!/bin/bash


echo ""
echo "###############################"
echo "## CUSTOM BUILD SCRIPT START ##"
echo ""

# Checking prerequisites
if [ "${DJANGO_SETTINGS_MODULE}" == "" ]
then
    echo "Error! Building arg 'DJANGO_SETTINGS_MODULE' empty!"
    exit 1
fi


#### Pip install ####
echo ""
echo "## PIP INSTALL ##"

# Generating requirements file from environment setting.
reqFile=`echo ${DJANGO_SETTINGS_MODULE} | awk -F. '{print $3".txt"}'`

echo "Updating modules using pip (${reqFile})... "

pip install --no-cache-dir -r /tmp/${reqFile}



#### Application source ####

echo ""
echo "## SETTING APPLICATION SOURCE ##"
# We set correct location for app source files
echo "Setting correct source for Django app..."

# If we have to use external source files for app (development purpose),
if [ "${DJANGO_SETTINGS_MODULE}" = "config.settings.local" ]
then
    echo "-> Using external source for app, deleting what was copied..."
    rm -rf ${TMP_APP_SOURCE_FILES}

else # We have to use internal source (Test or production, typically on OpenShift)

    echo "-> Using internal source for app, moving to correct place..."
    mv ${TMP_APP_SOURCE_FILES} /usr/src/

fi

if [ "${DJANGO_SETTINGS_MODULE}" = "config.settings.prod" ]
then
    echo ""
    echo "## STATIC FILES ##"
    echo "Creating directory... "
    mkdir -p /usr/src/xaas-admin/static/
    chmod -R 777 /usr/src/xaas-admin/static/
fi

echo ""
echo "## CUSTOM BUILD SCRIPT DONE ##"
echo "##############################"
echo ""
