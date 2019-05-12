#!/bin/sh
#/* *************************************************************************** 
#* Module 		: XXRL  
#* Script Name 	: RLYP_OPEN_PO_INV_REP_SH.sh
#* Description 	: Run the shell script to Upload the ldt files
#* Design 		: NA 
#* Current Ver 	: 1.0 
#**************************************************************************** 
#* Version# 	Date 			Author 			Description of changes 
#* 1.0 			04-Mar-2019 	Nagesh Kanna    Initial Draft
#*************************************************************************** */

echo " Set the parameters ....."
printf ' Enter APPS password:'
read APPS_PWD
if [ ${#APPS_PWD} -le 2 ]; then
   echo " APPS password is not entered"
   exit 1
fi

RC=0
echo "15563 RLYP Open PO Invoice Report"

echo "Uploading Concurrent Program"
# +===========================================================================+
#  Uploading Concurrent Program 
#      RLYP Open PO Invoice Report
# +===========================================================================+
echo 'Concurrent Program UPLOAD'

FNDLOAD apps/$APPS_PWD O Y UPLOAD $FND_TOP/patch/115/import/afcpprog.lct RLYP_OPEN_PO_INV_REP_CP.ldt CUSTOM_MODE=FORCE

echo 'Request Group UPLOAD'

FNDLOAD apps/$APPS_PWD 0 Y UPLOAD $FND_TOP/patch/115/import/afcpreqg.lct RLYP_OPEN_PO_INV_REP_RG.ldt CUSTOM_MODE=FORCE

echo 'Data Defination Upload'

FNDLOAD apps/$APPS_PWD 0 Y UPLOAD $XDO_TOP/patch/115/import/xdotmpl.lct RLYP_OPEN_PO_INV_REP_DD.ldt CUSTOM_MODE=FORCE

echo 'Data Template Upload'

FNDLOAD apps/$APPS_PWD  O Y UPLOAD  $XDO_TOP/patch/115/import/xdotmpl.lct RLYP_OPEN_PO_INV_REP_DT.ldt CUSTOM_MODE=FORCE


RC=$?
if [ $RC -eq 0 ]; then
        echo "Return Code=$RC"
else
        echo "Problem Problem Problem"
fi