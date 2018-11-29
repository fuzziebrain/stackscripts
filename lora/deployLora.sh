#!/bin/bash
## Variables
# CONFIGURABLE
## Versions
APEX_VERSION=18.2
ORDS_VERSION=18.3
## Download sources
ORACLE_PREINSTALL_RPM_URL=https://yum.oracle.com/repo/OracleLinux/OL7/latest/x86_64/getPackage/oracle-database-preinstall-18c-1.0-1.el7.x86_64.rpm
# CONFIGURABLE END
##### DO NOT CHANGE!!! #####
## Download directory
DOWNLOADS_DIR=/tmp/downloads
## Filenames
ORACLE_PREINSTALL_RPM=oracle-database-preinstall-18c-1.0-1.el7.x86_64.rpm
ORACLE_XE_RPM=oracle-database-xe-18c-1.0-1.x86_64.rpm
## Database
ORACLE_SID=XE
ORACLE_PDB_NAME=XEPDB1
ORACLE_BASE=/opt/oracle
ORACLE_HOME=${ORACLE_BASE}/product/18c/dbhomeXE
LISTENER_PORT=1521
EM_PORT=5500
EM_REMOTE_ENABLE=N
APEX_HOME=${ORACLE_BASE}/product/apex
ORDS_HOME=${ORACLE_BASE}/product/ords
## Miscellaneous
ORAENV_ASK=NO
## Commands
ORACLE_CMD=/etc/init.d/oracle-xe-18c
APEX_INSTALL=/tmp/installApex.sh
ORDS_INSTALL=/tmp/installOrds.sh
## Linode Stackscripts Override
ORACLE_PASSWORD=${SS_ORACLE_PASSWORD:-$ORACLE_PASSWORD}
ORACLE_CHARSET=${SS_ORACLE_CHARSET:-$ORACLE_CHARSET}
APEX_ADMIN_EMAIL=${SS_APEX_ADMIN_EMAIL:-$APEX_ADMIN_EMAIL}
APEX_ADMIN_PASSWORD=${SS_APEX_ADMIN_PASSWORD:-$APEX_ADMIN_PASSWORD}
SERVER_NAME=${SS_SERVER_NAME:-$SERVER_NAME}
SSL_ENABLED=${SS_SSL_ENABLED:-$SSL_ENABLED}
ORACLE_XE_RPM_URL=${SS_ORACLE_XE_RPM_URL:-$ORACLE_XE_RPM_URL}
APEX_ZIP_URL=${SS_APEX_ZIP_URL:-$APEX_ZIP_URL}
ORDS_ZIP_URL=${SS_ORDS_ZIP_URL:-$ORDS_ZIP_URL}
POST_DEPLOY_CLEANUP=#{SS_POST_DEPLOY_CLEANUP:-$POST_DEPLOY_CLEANUP}

echo "Setting additional variables"
case APEX_VERSION in
5.1.4)
  APEX_ZIP=apex_5.1.4.zip
  ;;
*)
  APEX_ZIP=apex_18.2.zip
  APEX_REST_CONFIG_PREFIX=@
  ;;
esac;

case ORDS_VERSION in
*)
  ORDS_ZIP=ords-18.3.0.270.1456.zip
  ;;
esac;

echo "Install packages"
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install -y \
    sudo \
    httpd \
    mod_ssl \
    java-1.8.0-openjdk-devel \
    tomcat \
    firewalld \
    certbot

echo "Download required files"
if [ ! -d "$DOWNLOADS_DIR" ]; then
    mkdir -p $DOWNLOADS_DIR
fi

FILES_TO_DOWNLOAD=( ORACLE_PREINSTALL_RPM ORACLE_XE_RPM APEX_ZIP ORDS_ZIP )

mkdir -p $DOWNLOADS_DIR && cd $DOWNLOADS_DIR

for file in "${FILES_TO_DOWNLOAD[@]}";
do
  eval SOURCE=\$${file}_URL;
  eval TARGET=\$$file;
  echo Downloading $TARGET from $SOURCE;
  curl --progress-bar -L -o $TARGET $SOURCE;
done;

echo "Install Oracle XE binaries"
yum localinstall -y $ORACLE_PREINSTALL_RPM 
# Fix problem with su
# sed -i 's!^\(oracle *hard *memlock\)!#\1!g' /etc/security/limits.d/oracle-database-preinstall-18c.conf
yum localinstall -y $ORACLE_XE_RPM 

echo "Prepare database configuration"
cat << EOF > /etc/sysconfig/oracle-xe-18c.conf
#This is a configuration file to setup the Oracle Database. 
#It is used when running '/etc/init.d/oracle-xe-18c configure'.

# LISTENER PORT used Database listener, Leave empty for automatic port assignment
LISTENER_PORT=${LISTENER_PORT:-1521}

# EM_EXPRESS_PORT Oracle EM Express URL port
EM_EXPRESS_PORT=${EM_PORT:-5500}

# Character set of the database
CHARSET=${ORACLE_CHARSET:-AL32UTF8}

# Database file directory
# If not specified, database files are stored under Oracle base/oradata
DBFILE_DEST=

# SKIP Validations, memory, space
SKIP_VALIDATIONS=false
EOF

echo "Configure database"
(echo "${ORACLE_PASSWORD}"; echo "${ORACLE_PASSWORD}";) | ${ORACLE_CMD} configure

echo "Update listener and tnsnames"
sed -i 's/'$(hostname)'/0.0.0.0/g' $ORACLE_HOME/network/admin/listener.ora
sed -i 's/'$(hostname)'/0.0.0.0/g' $ORACLE_HOME/network/admin/tnsnames.ora

echo "Create installApex.sh script"
cat > ${APEX_INSTALL} <<EOF0
#!/bin/bash

APEX_ZIP=$APEX_ZIP
ORAENV_ASK=$ORAENV_ASK
ORACLE_SID=$ORACLE_SID

. oraenv 

unzip ${DOWNLOADS_DIR}/${APEX_ZIP} -d ${ORACLE_BASE}/product/ 

cd ${APEX_HOME}

sqlplus / as sysdba << EOF
  alter session set container = ${ORACLE_PDB_NAME:-XEPDB1};

  -- Install APEX
  @apexins.sql SYSAUX SYSAUX TEMP /i/

  -- APEX REST configuration
  @apex_rest_config_core.sql $APEX_REST_CONFIG_PREFIX "${APEX_LISTENER_PASSWORD:-$ORACLE_PASSWORD}" "${APEX_REST_PUBLIC_USER_PASSWORD:-$ORACLE_PASSWORD}"

  -- Required for ORDS install
  alter user apex_public_user identified by "${APEX_PUBLIC_USER_PASSWORD:-$ORACLE_PASSWORD}" account unlock;

  -- Network ACL
  prompt Setup Network ACL
  begin
    for c1 in (
      select schema
      from sys.dba_registry
      where comp_id = 'APEX'
    ) loop
      sys.dbms_network_acl_admin.append_host_ace(
        host => '*'
        , ace => xs\\\$ace_type(
            privilege_list => xs\\\$name_list('connect')
            , principal_name => c1.schema
            , principal_type => xs_acl.ptype_db
        )
      );
    end loop;
    commit;
  end;
  /

  -- Setup APEX Admin account
  prompt Setup APEX Admin account
  begin
    apex_util.set_workspace(p_workspace => 'internal');
    apex_util.create_user(
      p_user_name => 'ADMIN'
      , p_email_address => '${APEX_ADMIN_EMAIL}'
      , p_web_password => '${APEX_ADMIN_PASSWORD}'
      , p_developer_privs => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL'
      , p_change_password_on_first_use => 'N'
    );
    commit;
  end;
  /

  -- Create profile APPLICATION_AGENT
  create profile application_agent limit
    cpu_per_session unlimited
    cpu_per_call unlimited
    connect_time unlimited
    idle_time unlimited
    sessions_per_user unlimited
    logical_reads_per_session unlimited
    logical_reads_per_call unlimited
    private_sga unlimited
    composite_limit unlimited
    password_life_time unlimited
    password_grace_time 7
    password_reuse_max unlimited
    password_reuse_time unlimited
    password_verify_function null
    failed_login_attempts 10
    password_lock_time 1
  ;

  -- Assign relevant users so that their passwords do not expire
  alter user apex_public_user profile application_agent;
  alter user apex_rest_public_user profile application_agent;
  alter user apex_listener profile application_agent;
EOF
EOF0
chmod a+x $APEX_INSTALL

echo "Install APEX"
runuser -l oracle -c $APEX_INSTALL > /tmp/apexInstall.log 2>&1

echo "Create ORDS install script"
cat > ${ORDS_INSTALL} <<EOF0
#!/bin/bash

ORDS_ZIP=$ORDS_ZIP
ORAENV_ASK=$ORAENV_ASK
ORACLE_SID=$ORACLE_SID
ORDS_CONFIG_DIR=${ORDS_HOME}/conf

. oraenv 

unzip ${DOWNLOADS_DIR}/${ORDS_ZIP} -d ${ORDS_HOME}

cd ${ORDS_HOME}

cat << EOF > ${ORDS_HOME}/params/custom_params.properties
db.hostname=localhost
db.password=${APEX_PUBLIC_USER_PASSWORD:-$ORACLE_PASSWORD}
db.port=${LISTENER_PORT:-1521}
db.servicename=${ORACLE_PDB_NAME:-XEPDB1}
db.username=APEX_PUBLIC_USER
plsql.gateway.add=true
rest.services.apex.add=true
rest.services.ords.add=true
standalone.mode=false
schema.tablespace.default=SYSAUX
schema.tablespace.temp=TEMP
user.apex.listener.password=${APEX_LISTENER_PASSWORD:-$ORACLE_PASSWORD}
user.apex.restpublic.password=${APEX_LISTENER_PASSWORD:-$ORACLE_PASSWORD}
user.public.password=${ORDS_PUBLIC_USER_PASSWORD:-$ORACLE_PASSWORD}
user.tablespace.default=SYSAUX
user.tablespace.temp=TEMP
sys.user=sys
sys.password=${ORACLE_PASSWORD}
EOF

java -jar ords.war configdir \${ORDS_CONFIG_DIR}

java -jar ords.war install simple --parameterFile ${ORDS_HOME}/params/custom_params.properties

sqlplus / as sysdba << EOF
  alter session set container = ${ORACLE_PDB_NAME:-XEPDB1};
  alter user ords_public_user profile application_agent;
EOF
EOF0
chmod a+x $ORDS_INSTALL

echo "Install ORDS"
runuser -l oracle -c $ORDS_INSTALL  > /tmp/ordsInstall.log 2>&1

echo "Configure Apache2"
cat > /etc/httpd/conf.d/apex_images.conf <<EOF
Alias /i "${APEX_HOME}/images/"

<Directory "${APEX_HOME}/images/">
    Options None
    AllowOverride None
    Require all granted
</Directory>
EOF

if [ ${SSL_ENABLED^^} == 'Y' ]; then
  cat > /etc/httpd/conf.d/apex_proxies.conf <<EOF
<VirtualHost *:80>
  ServerName ${SERVER_NAME}

  RewriteEngine On
  RewriteCond %{HTTPS} off
  RewriteRule (.*) https://%{SERVER_NAME}/\$1 [R,L]
</VirtualHost>

<VirtualHost *:443>
  ServerName ${SERVER_NAME}

  SSLEngine on
  SSLProtocol all -SSLv2 -SSLv3
  SSLCipherSuite HIGH:3DES:!aNULL:!MD5:!SEED:!IDEA
  SSLProxyEngine on
  SSLProxyCheckPeerCN off
  SSLProxyCheckPeerExpire off
  SSLProxyCheckPeerName off

  ErrorLog logs/ssl_error_log
  TransferLog logs/ssl_access_log
  LogLevel warn
  CustomLog logs/ssl_request_log \
          "%t %h %{SSL_PROTOCOL}x %{SSL_CIPHER}x \"%r\" %b"

  ProxyPreserveHost on
  ProxyAddHeaders on
  ProxyPass /ords https://localhost:8443/ords
  ProxyPassReverse /ords https://localhost:8443/ords

  RewriteEngine On
  RewriteRule "^/\$" "/ords" [R]

  SSLCertificateFile /etc/pki/tls/certs/localhost.crt
  SSLCertificateKeyFile /etc/pki/tls/private/localhost.key
  #SSLCertificateChainFile /etc/pki/tls/certs/server-chain.crt
</VirtualHost>
EOF
else
  cat > /etc/httpd/conf.d/apex_proxies.conf <<EOF
<VirtualHost *:80>
  ServerName ${SERVER_NAME}

  ProxyPreserveHost on
  ProxyAddHeaders on
  ProxyPass /ords http://localhost:8080/ords
  ProxyPassReverse /ords http://localhost:8080/ords

  RewriteEngine On
  RewriteRule "^/\$" "/ords" [R]
</VirtualHost>
EOF
fi

echo "Deploy ORDS"
if [ ${SSL_ENABLED^^} == 'Y' ]; then
  keytool -genkey -alias tomcat -validity 3650 -keystore /etc/tomcat/.keystore \
    -storepass secureOrds -keypass secureOrds \
    -dname "CN=localhost, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=Unknown";

  sed -i -r '/<!--/N;s/<!--\s+(<Connector port=\"8443\".+)$/\1/' /etc/tomcat/server.xml;
  sed -i -r "/<Connector port=\"8443\".+$/ a \               keystoreFile=\"/etc/tomcat/.keystore\" keystorePass=\"secureOrds\"" /etc/tomcat/server.xml;
  sed -i -r '/clientAuth="false" sslProtocol="TLS" \/>/N;s/(clientAuth="false" sslProtocol="TLS" \/>)\s+-->/\1/' /etc/tomcat/server.xml;
fi

cp ${ORDS_HOME}/ords.war /var/lib/tomcat/webapps/

echo "SELinux configurations"
if [[ -n "$(command -v getenforce)" ]] && [[ $(getenforce) == "Enforcing" ]]; then
  semanage fcontext -a -t tomcat_var_run_t '${ORDS_HOME}/conf(/.*)?'
  restorecon -R -v ${ORDS_HOME}/conf
  semanage fcontext -a -t tomcat_var_run_t '/var/lib/tomcat/webapps(/.*)?'
  restorecon -R -v /var/lib/tomcat/webapps
  setsebool -P httpd_can_network_connect 1
fi

echo "Enabling services"
systemctl daemon-reload
systemctl enable oracle-xe-18c
systemctl enable tomcat
systemctl enable httpd
systemctl enable firewalld

echo "Start services"
systemctl start tomcat
systemctl start httpd
systemctl start firewalld

echo "Configure and reload firewall"
firewall-cmd --zone=public --add-service http --permanent
firewall-cmd --zone=public --add-service https --permanent
systemctl reload firewalld

echo "Clean up"
if [ ${POST_DEPLOY_CLEANUP^^} == 'Y' ]; then
  rm -rf ${DOWNLOADS_DIR} $APEX_INSTALL $ORDS_INSTALL
fi

echo "##### Deployment Complete #####"