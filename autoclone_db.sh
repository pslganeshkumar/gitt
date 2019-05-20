# #######################################################################################################
#  Execution of the script should be DBTier Tier:
#  Execution: $ sh autoclone_db.sh | tee -a /export/home/oranprd/postclone/autoclone_$(date "+%m-%d-%y").log 
# #######################################################################################################

. $HOME/par.env

function prompting {
        response=""
        unset response
        print " "
        print "${1}"
        print "Valid responses: 'abort(A)', 'skip(S)', 'continue(DEFAULT ENTER)'."
        read response
           if [[ -z ${response} ]]; then
                unset response
                response="${response:-continue}" 
                return 0
          elif [[ ${response} == "A" ]]; then
                abort_script "Aborting."
                exit 1
          elif [[ ${response} == "S" ]]; then
                return 2
          elif [[ ${response} == "continue" ]]; then
                return 0
          #else
                #return 1
          fi

}


function abort_script {
        print "${1}"
        exit 1
}




echo " ######### STARTING Cloning Process ############## " 
echo "" 
echo "" 

echo " setting Environment  ............." 
echo "" 
echo "" 

####################### DROP DATABASE ####################################################

function shutdown_db {
echo " ########## Shutting down the Instance #############"
echo ""
echo ""

sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
spool $HOME/shut.log
select instance_name, status from v\$instance;
shut immediate
spool off
exit
EOF
}

###################  CHECKING PARAMETER FILE PARMETERS ##########################################

function check_iniora {

echo ########## cross checking Parameter values in init.ora #############"
echo ""
echo ""
grep -i convert $ORACLE_HOME/dbs/init$ORACLE_SID.ora
}

####################### create password file ###############################################

function recreate_pwdfile {
echo  " Recreating password file ......... "
echo ""
echo ""
cd $ORACLE_HOME/dbs
mv -i $ORACLE_HOME/dbs/orapw$ORACLE_SID $ORACLE_HOME/dbs/orapw$ORACLE_SID_$(date "+%m-%d-%y-%H:%M:%S")
orapwd file=$ORACLE_HOME/dbs/orapw$ORACLE_SID password=$SYS_PWD Entries=5
}

############################# DROPPING DATABASE #############################

function drop_db {

echo " ########## Dropping the database ..........."
echo ""
echo ""


sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
startup mount exclusive restrict
select instance_name, status from v\$instance;
drop database;
exit
EOF

}

function dropdb_recreatepwdfile {

shutdown_db

unset SHUT_CHK
SHUT_CHK=`grep -i "ORACLE instance shut down" $HOME/shut.log|wc -l`
if [ "$SHUT_CHK" -eq 1 ]; then

drop_db

else
   echo "Cannot drop database.Database is up and running, waiting for three more minutes to execute next step, please shutdown databse manually"
   sleep 3m;
   drop_db
fi

check_iniora

if [ "$SHUT_CHK" -eq 1 ]; then

recreate_pwdfile

else 
    echo "cannot recreate password file database is still up and running, script will wait for three minutes to recreate password file meanwhile shutdown the database"
    sleep 2m;
    recreate_pwdfile
fi
}


####################### RMAN RESTORE ###########################################

function start_nomount {
echo "########## starting database in nomount #############"
echo ""
echo ""
sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
spool $HOME/nomount_check.log
startup nomount
spool off
exit
EOF
}
###### RMAN DUPLICATE COMMAND #############


function rman_restore {

echo "########## Starting RMAN Restore #############"
echo ""
echo ""
cd $DIR
sh $DIR/rman_restore.sh
#rman @rman_restore.rmn
}

function startupnomount_rman_restore {

start_nomount

unset NMCHK
NMCHK=`grep -i STARTED $HOME/nomount_check.log|wc -l` 
if [ "$NMCHK" -eq 1 ]; then

rman_restore

else 
    echo "database instance not in no mount please start the instance in nomount, RMAN script will execute in 3 minutes. "
    echo ""
    sleep 3m;
    rman_restore
fi
}
##################################### CREATING SPFILE FROM PFILE ###################################

function stop_lsnr {
echo " Stopping listener services ............."
echo ""
echo ""

lsnrctl stop $ORACLE_SID
}

function shut_database {
echo " ########## Shutting down the Instance #############"
echo ""
echo ""

sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
select instance_name, status from v\$instance;
shut immediate
exit
EOF
}

function start_spfile {

echo " Starting Database Instance and creating spfile ..........."
echo ""
echo ""
sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
startup
select instance_name, status from v\$instance;
show parameter spfile
create spfile from pfile;
exit
EOF


}

function startdb_spfile_trunc_conc_fndnodes_cmclean {

stop_lsnr

shutdown_db

unset SHUT_CHK
SHUT_CHK=`grep -i "ORACLE instance shut down" $HOME/shut.log|wc -l`
if [ "$SHUT_CHK" -eq 1 ]; then

start_spfile

else
   echo "Cannot startup database and create spfile.Database is still up and running, waiting for two more minutes to execute the step, please shutdown databse manually"
   sleep 3m;
   start_spfile
fi

shutdown_db

unset SHUT_CHK
SHUT_CHK=`grep -i "ORACLE instance shut down" $HOME/shut.log|wc -l`
if [ "$SHUT_CHK" -eq 1 ]; then

startup_db

else
   echo "Cannot startup database, Database is still up and running, waiting for two more minutes to execute the step, please shutdown databse manually"
   sleep 3m;
   startup_db 
fi

unset STRT_CHK
STRT_CHK=`grep -i "Database opened" $HOME/startup.log|wc -l`

if [ "$STRT_CHK" -eq 1 ]; then

truncate_concreq

truncate_fndnodes

cmclean

else 

    echo " Cannot truncate concrequest, fnd nodes table and cannot run cmclean as  database is not in open state. script will wait for 2 minutes to execute this step"
    sleep 2m;
    truncate_concreq
    truncate_fndnodes
    cmclean
fi

}

function startup_db {
echo " Starting Database Instance ............"
echo ""
echo ""
sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
spool $HOME/startup.log
startup
spool off
show parameter spfile
exit
EOF
}

####################################### TRUNCATING CONCURRENT REQUESTS ##################################

function truncate_concreq {
echo " ###################### Truncating All Concurrent Requests ##############"
echo ""
echo ""

sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
truncate table applsys.fnd_concurrent_requests;
select count(*) from applsys.fnd_concurrent_requests;
exit
EOF
}

###################################### TRUNCATING FND NODES #################################

function truncate_fndnodes {
echo " ###################### Truncating FND NODES ###########"
echo ""
echo ""
#print "enter Prod apps password :"
#read APPS_PWD

sqlplus -s apps/$APPS_PWD << EOF
whenever sqlerror exit sql.sqlcode;
show user
exec fnd_conc_clone.setup_clean;
commit;
exit
EOF
}


function cmclean {
echo " executing Cmclean.sql ........."
echo ""
echo ""
#print "enter Prod apps password :"
#read APPS_PWD
sqlplus -s apps/$APPS_PWD << EOF
whenever sqlerror exit sql.sqlcode;
show user
@/mnt/scripts/cmclean.sql 
dual
commit;
exit
EOF
}

###################################  RUNNING AUTOCONFIG  #####################################

function start_lsnr {
echo "Starting Listener Services ......."
echo ""
echo ""

lsnrctl start $ORACLE_SID
}

function autoconfig {

echo " ######## Running Autoconfig on DB Side ######## "
echo ""
echo ""

cd $ORACLE_HOME/appsutil/scripts/$CONTEXT_NAME
sh $ORACLE_HOME/appsutil/scripts/$CONTEXT_NAME/adautocfg.sh <<EOF
$APPS_PWD
EOF
}

function startlistener_autoconfig {

start_lsnr

unset LSNR_CHK
LSNR_CHK=`ps -ef | grep -i tns | grep -i $ORACLE_SID | wc -l`

if [ "$LSNR_CHK" -eq 1 ]; then

autoconfig

else

    echo " Listener status is down.Please start listener before running autoconfig, otherwise autoconfig will fail. script will wait for 2 mins to execute the step again."
    sleep 2m;
    autoconfig
fi

}

function sys_system_pwd_change {
        
        #stty -echo
        #read SYS_PWD
        #stty echo

        if [[ -z ${SYS_PWD} ]]; then
                abort_script "Empty password."
        fi

        #print " Enter the NEW SYSTEM password:"

        #stty -echo
        #read SYSTEM_PWD
        #stty echo

        if [[ -z ${SYSTEM_PWD} ]]; then
                abort_script "Empty password."
        fi

        sqlplus "/ as sysdba" << EOF
ALTER USER SYS IDENTIFIED BY ${SYS_PWD};
ALTER USER SYSTEM IDENTIFIED BY ${SYSTEM_PWD};
EXIT
EOF
}


###################################### APPLICATION CLONING ###########SAN#########

function switch_adcfg {

LOG=$DIR/autoclone_$(date "+%m-%d-%y").log
ssh $APPL_NODE ". ~/par.env;sh $APPS_DIR/appsclone.sh $APPS_PWD" 
}

#############################################################################################

###################################### DB POST CLONES ###################################

function tnsnames_copy {

echo "###### copying tnsnames.ora from backend and checking in path ########"
echo ""
echo ""

cp $DIR/tnsnames.ora $TNS_ADMIN
ls -lrt $TNS_ADMIN/tnsnames.ora

echo ""
echo ""

}

function db_directories {
echo " ########## creating Directories in Database level #######"
echo ""
echo ""

cd $DIR
ls -lrt direct*

sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
select instance_name, status from v\$instance;
select count(DIRECTORY_NAME) from dba_directories;
@directories.sql
select count(DIRECTORY_NAME) from dba_directories;
exit
EOF

echo ""
echo ""

}

function server_directories {
echo " ########## creating Directories in Server level #######"
echo ""
echo ""

cd $DIR
sh $DIR/db_directories.sh

}

############DB LINK CREATION##############################

function db_link_db {
echo " ########## Database Link creation ###### "
echo ""
echo ""
cd $DIR
sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
col OWNER for a10
col DB_LINK for a50
col USERNAME for a15
col HOST for a20
set lines 300
set pages 100
select * from dba_db_links;

drop public database link ${SRC_SID}_TO_${SRC_ASCP}.DDOPAAS.COM;
drop public database link SABRIX_TO_SBXAUD.DDOPAAS.COM;
drop public database link SABRIX_TO_SBXTAX.DDOPAAS.COM;
create public database link ${DEST_SID}_TO_${DEST_ASCP} connect to apps identified by ${APPS_PWD_NEW} using '${DEST_ASCP}';
create public database link SABRIX_TO_SBXAUD connect to sbxaud identified by sbxaud using 'SABNTX';
create public database link SABRIX_TO_SBXTAX connect to sbxtax identified by sbxtax using 'SABNTX';
create database link APPS_TO_APPS.DDOPAAS.COM connect to apps identified by ${APPS_PWD_NEW} using '${DEST_SID}';


conn apps/${APPS_PWD}

drop database link EBSAGILE.DDOPAAS.COM;
CREATE DATABASE LINK "EBSAGILE.DDOPAAS.COM" CONNECT TO AGILE IDENTIFIED BY tartan USING '${AGILE_HOST}:1521/${AGILE_SID}';
drop database link APPS_TO_APPS.DIDATA.LOCAL;
drop database link EDW_APPS_TO_WH.DIDATA.LOCAL;
drop database link EDW_APPS_TO_WH.DDOPASS.COM;
drop database link EDW_APPS_TO_WH;
drop database link EDW_APPS_TO_WH.US.ORACLE.COM;
drop database link APPS_TO_APPS.DDOPASS.COM;
drop database link APPS_TO_APPS.US.ORACLE.COM;

#@create_droplinks.sql $SRC_SID $SRC_ASCP $DEST_SID $DEST_ASCP $APPS_PWD_NEW $AGILE_HOST $AGILE_SID $APPS_PWD

select count(DB_LINK) from dba_db_links;
exit
EOF

}
############ ADDING SPACE TO TEMP TABLESPACE##############################
function temp_tablespace {
echo ""
echo ""
echo " ########## RESIZING TEMP TABLESPACE ###### "
echo ""
echo ""

sqlplus -s '/ as sysdba' << EOF
whenever sqlerror exit sql.sqlcode;
select tablespace_name from dba_temp_files;
ALTER DATABASE TEMPFILE '$TEMP_TBS/temp01.dbf' resize 4096m;
ALTER DATABASE TEMPFILE '$TEMP_TBS/temp02.dbf' resize 4096m;
ALTER DATABASE TEMPFILE '$TEMP_TBS/temp05.dbf' resize 4096m;
exit
EOF

}

function rman_configure {

echo " ######### Configuring RMAN Paramneters ############ "
echo ""
echo ""

cd $DIR
sh $DIR/rman_run_shell.sh

echo ""
echo ""

echo " ##### DB SIde Post Clones completed check logfile for any errors, now switching to application node for executing application postclones #######"

}


function db_postclones {

unset STRT_CHK
STRT_CHK=`grep -i "Database opened" $HOME/startup.log|wc -l`

if [ "$STRT_CHK" -eq 1 ]; then

sys_system_pwd_change

else

    echo " cannot change sys and system password. database is not opened, please start database, this script will wait for 3 minutes to start database"
    sleep 3m;
    sys_system_pwd_change
fi

tnsnames_copy

stop_lsnr

shutdown_db

start_lsnr

unset SHUT_CHK
SHUT_CHK=`grep -i "ORACLE instance shut down" $HOME/shut.log|wc -l`
if [ "$SHUT_CHK" -eq 1 ]; then

startup_db

else
   echo "Cannot startup database, Database is still up and running, waiting for two more minutes to execute the step, please shutdown databse manually"
   sleep 3m;
   startup_db
fi

unset STRT_CHK
STRT_CHK=`grep -i "Database opened" $HOME/startup.log|wc -l`

if [ "$STRT_CHK" -eq 1 ]; then

     db_directories

     server_directories

     db_link_db

     temp_tablespace

     rman_configure

else

    echo " cannot change sys and system password. database is not opened, please start database, this script will wait for 3 minutes to start database"
    sleep 3m;

    db_directories

    server_directories

    db_link_db

    temp_tablespace

    rman_configure

fi

}


########### END OF DB POSTCLONES ##############


########################################### APPLICATION POST CLONES #################SAN###############




function setenv {

ssh $APPL_NODE "$APPS_DIR/setenv.sh"

}

function apps_sysadmin_pwd {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/apps_applsys_pwd.sh $APPS_PWD $SYSTEM_PWD $APPS_PWD_NEW $SYSADMIN_PWD"

}

function autoconfig_apps {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/autoconfig_apps.sh $APPS_PWD_NEW"
 
}

function frontend_user_pwd {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/frontend_user_pwd.sh $APPS_PWD_NEW"
 
}

function create_direct_server_level {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/create_direct_server.sh"

}

function cust_exec_assign_hist_sql {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/exec_assign_hist_sql.sh $APPS_PWD_NEW"

}

function cust_exec_salary_hist_sql {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/exec_salary_hist_sql.sh $APPS_PWD_NEW"

}

function cust_exec_hr_scrub_sql {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/exec_hr_scrub_sql.sh $APPS_PWD_NEW"

}

function cust_postclone {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/exec_postclone_sql.sh $APPS_PWD_NEW"

}

function cust_creditcard {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/exec_creditcard_sql.sh $APPS_PWD_NEW"

}

function gif_jpg_copy {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/copy_gif_jpg_files.sh"

}

function os_files_softlink {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/os_files_softlink.sh"

}

function sabrix_p2p {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/sabrix_p2p.sh $APPS_PWD_NEW"

}

function sabrix_o2c {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/sabrix_o2c.sh $APPS_PWD_NEW"

}

function dblink_check {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/dblink_check_apps.sh $SYSTEM_PWD"

}

function update_ftp_details {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/update_ftp_details.sh $APPS_PWD_NEW"

}

function copy_mwa_services_startup {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/copy_mwa_services_startup.sh $APPS_PWD_NEW"

}

function update_profile_value {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/update_profile_values.sh $APPS_PWD_NEW"

}

function add_resp_to_users {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/add_resp_to_users.sh $APPS_PWD_NEW"

}

function printer_backend_setup {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/printer_backend_setup.sh $APPS_PWD_NEW"

}

function workflow_conc_schedule {

ssh $APPL_NODE ". ~/.profile; sh $APPS_DIR/function/schedule_conc_programs.sh $APPS_PWD_NEW"

}

function apps_applsys_pwd_change_autoconfig {

apps_sysadmin_pwd

unset check
check=$(sqlplus  APPS/$APPS_PWD_NEW@$ORACLE_SID <<EOF
whenever sqlerror exit sql.sqlcode;
exit
EOF
)

unset db_cond
db_cond=`echo -e "\n${check}" | grep -i 'Connected to:'`

if [ "$db_cond" = "Connected to:" ]; then

     autoconfig_apps

else

   echo " APPS PASSWORD was not changed, please change the password again, script will wait for 3 mins to run this step again "

   autoconfig_apps

fi

}

function application_postclones {

unset check
check=$(sqlplus  APPS/$APPS_PWD_NEW@$ORACLE_SID <<EOF
whenever sqlerror exit sql.sqlcode;
exit
EOF
)

unset db_cond
db_cond=`echo -e "\n${check}" | grep -i 'Connected to:'`

if [ "$db_cond" = "Connected to:" ]; then

     frontend_user_pwd

     create_direct_server_level

     cust_exec_assign_hist_sql

     cust_exec_salary_hist_sql

     cust_exec_hr_scrub_sql

     cust_postclone

     cust_creditcard

     gif_jpg_copy

     os_files_softlink

     sabrix_p2p

     sabrix_o2c

     dblink_check

     update_ftp_details

     copy_mwa_services_startup

     update_profile_value

     add_resp_to_users

     printer_backend_setup

     workflow_conc_schedule

else

   echo " APPS PASSWORD was not changed, please change the password again, script will wait for 3 mins to run this step again "

   frontend_user_pwd

   create_direct_server_level

   cust_exec_assign_hist_sql

   cust_exec_salary_hist_sql

   cust_exec_hr_scrub_sql

   cust_postclone

   cust_creditcard

   gif_jpg_copy

   os_files_softlink

   sabrix_p2p

   sabrix_o2c

   dblink_check

   update_ftp_details

   copy_mwa_services_startup

   update_profile_value

   add_resp_to_users

   printer_backend_setup

   workflow_conc_schedule

fi

}


##########################################################################################functions calling ######################################################

print " Enter the PROD APPS Password:"

#stty -echo
read APPS_PWD
#stty echo

echo " Enter NON Prod apps password :"

#stty -echo
read APPS_PWD_NEW
#stty echo

echo " Enter NON Prod SYS password :"

#stty -echo
read SYS_PWD
#stty echo

echo " Enter NON Prod SYSTEM password :"

#stty -echo
read SYSTEM_PWD
#stty echo

echo " Enter NON Prod Sysadmin Password :"

#stty -echo
read SYSADMIN_PWD
#stty echo

prompting " STEP1: dropping the database ........."
prompt_rc=${?}
case ${prompt_rc} in
        "0")            dropdb_recreatepwdfile
                        ;;
        "1")            abort_script "Invalid response." 
                        ;;
esac


prompting " STEP2: Duplicating database using  RMAN "
prompt_rc=${?}
case ${prompt_rc} in
        "0")            startupnomount_rman_restore
                        ;;
        "1")            abort_script "Invalid response." 
                        ;;
		esac


prompting " STEP3: Starting up the instance and creating spfile "
prompt_rc=${?}
case ${prompt_rc} in
        "0")            startdb_spfile_trunc_conc_fndnodes_cmclean
                        ;;
        "1")            abort_script "Invalid response." 
                        ;;
esac


prompting " STEP4: Preparing to run autoconfig in dbtier .... "
prompt_rc=${?}
case ${prompt_rc} in
        "0")            startlistener_autoconfig
                        ;;
        "1")            abort_script "Invalid response." 
                        ;;
esac

prompting " STEP5: Switching to Application node to run adcfgclone ...... "
prompt_rc=${?}
case ${prompt_rc} in
        "0")            switch_adcfg 
                        ;;
        "1")            abort_script "Invalid response." 
                        ;;
esac


prompting " STEP6: DB Tier Post clone steps ...... "
prompt_rc=${?}
case ${prompt_rc} in
        "0")            db_postclones
                        ;;
        "1")            abort_script "Invalid response."
                        ;;
esac


prompting " STEP7: changing apps and sysadmin password and autoconfig and application postclones....... "
prompt_rc=${?}
case ${prompt_rc} in
        "0")            apps_applsys_pwd_change_autoconfig
                        ;;
        "1")            abort_script "Invalid response."
                        ;;
esac


prompting " STEP8: Application Postclones..... "
prompt_rc=${?}
case ${prompt_rc} in
        "0")            application_postclones
                        ;;
        "1")            abort_script "Invalid response."
                        ;;
esac


prompting " Press continue or enter to exit the clone script.... "
prompt_rc=${?}
case ${prompt_rc} in
        "0")            return 1 
                        ;;
        "1")            abort_script "Invalid response." 
                        ;;
esac
