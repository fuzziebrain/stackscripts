# Lora

This StackScript creates a [Linode](https://www.linode.com/?r=41672b20d515344de465e9ed44c1a75356445597) with three components necessary for APEX development.

> Fun Fact: Lora means **L**inode **O**racle Database, **R**EST and **A**PEX stack

## Obtaining the Installation Files

At the moment, only the software versions below are supported. The plan is to allow developers to choose between major versions of APEX (5.1.x, 18.x) in a future release.

| Component | Version | Expected Filename |
| - | - | - |
| [Oracle Database 18c Express Edition](https://oracle.com/xe) (XE) | 18.4 | oracle-database-xe-18c-1.0-1.x86_64.rpm |
| [Oracle REST Data Services](https://www.oracle.com/database/technologies/appdev/rest.html) (ORDS) | 18.3 | ords-18.3.0.270.1456.zip |
| [Oracle Application Express](https://apex.oracle.com) (APEX) | 18.2 | apex_18.2.zip |

Host these files on a publicly available web server, or to [Dropbox](https://db.tt/aNHVbSGN) and then follow the [instructions](https://www.dropbox.com/help/files-folders/view-only-access#link) to create a shareable link.

> Note: A new Dropbox account starts at 2 GB. Participating in the [various tasks](https://www.dropbox.com/help/space/get-more-space) will help you gain a few more MBs.

## Deploying a Linode

The new XE database requires at least 1 GB of RAM to install and run. Nanode, the smallest sized Linode that can be deployed, will not be sufficient. A Linode with 2 GB RAM is a minimum.

There are two versions of Linode Manager currently available. Use the appropriate guide for deploying Linodes using StackScripts

* Linode Cloud Manager *NEW* - https://www.linode.com/docs/platform/stackscripts-new-manager/
* Linode Manager - https://www.linode.com/docs/platform/stackscripts/

The following parameters are required:

| Parameter Name | Description | Default | Example |
| - | - | - | - |
| Oracle Database Password | Oracle Database password for `SYS`, `SYSTEM` and `PDBADMIN` users. The same password is used for the database accounts required for APEX and ORDS to function. In future, we may allow developers to set these as parameters. | - | Oracle18 |
| Oracle Database Characterset | Characterset used for the database. | AL32UTF8 | AL32UTF8 |
| Email Address for APEX Instance Administrator | Self-explanatory | - | dunsendme@spam.mail |
| Domain Name | Fully-Qualified Domain Name | - | lora.fuzziebrain.com |
| SSL Enabled | Setup SSL for the Apache2 HTTPD Web and Tomcat servers. | Y | Y |
| Link to Oracle 18c XE RPM File | Link to the Oracle XE RPM file. | - | https://www.dropbox.com/s/xxxxxxxxxxxxxxx/oracle-database-xe-18c-1.0-1.x86_64.rpm?dl=0 |
| Link to APEX ZIP File | Link to the APEX installer file. | - | https://www.dropbox.com/s/xxxxxxxxxxxxxxx/apex_18.2.zip?dl=0 |
| Link to ORDS ZIP File | Link to the ORDS installer file. | - | https://www.dropbox.com/s/xxxxxxxxxxxxxxx/ords-18.3.0.270.1456.zip?dl=0 |
| Post-deployment Cleanup | Whether to remove downloaded files and temporary scripts. Logs are always left in the `/tmp` directory. | Y | Y |
| Select Image | Operating System | CentOS 7 | CentOS 7 |
| Region | Server region | - | US (Freemont, CA) |
| Linode Plan | Size and prize of Linode required | - | Linode 2GB |
| Linode Label | A name for the Linode. Required later. | - | Lora |
| Add Tags | Tags if required | - | - |
| Root Password | Password for the Linode's root user | - | - |
| Backups | Linode backups. Charges apply. | - | - |
| Private IP | An additional private IP address for communication between Linodes within the same region. No charge. | - | - |

> **IMPORTANT** 
> 
> *A Note About Passwords*
> 
> While it is highly recommended to set passwords with maximum strength, sometimes, special characters may break the installation script.
> 
> * For Oracle Database Password, set a longer temporary password that meets Oracle minimal requirements of:
>
>     * At least 8 characters
>     * Contains at least 1 uppercase character
>     * Contains at least 1 lowercase character
>     * Contains at least 1 digit [0-9] 
>
>   Change these after the stack has been deployed successfully, introducing special characters.
> * Do the same for the APEX Instance Administrator's Password. Substitute for a stronger, more complex password, after APEX is up and running.

## Monitoring Progress

It takes about 30-60 minutes to complete the installation depending on the download speeds. The StackScript runs in the background and pipes all standard errors and output to the file `/tmp/loraDeploy.log`. The APEX and ORDS scripts are executed independently and will store the logs in the files `/tmp/apexInstall.log` and `/tmp/ordsInstall.log` respectively.

Use SSH to logon to the server as `root`. Get a real-time upgrade on progress with a simple command like:

```bash
$ tail -f /tmp/loraDeploy.log
```

## Post-Deployment Notes

* Check that APEX is up and running. If `SSL_ENABLED` was set, simply entering the IP address of the Linode will redirect to the APEX App Builder.
* Update the DNS entry for the brand new server.
* [Certbot](https://certbot.eff.org/) is installed during the deployment process. If `SSL_ENABLED`, use `certbot` to request the necessary SSL certificate, key and chain. Update the HTTPD configuration file `/etc/httpd/conf.d/apex_proxies.conf`. The last few lines of the configuration should look something like this:

```
<VirtualHost *:443>
  ...
  
  SSLCertificateFile /etc/letsencrypt/live/lora.fuzziebrain.com/cert.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/lora.fuzziebrain.com/privkey.pem
  SSLCertificateChainFile /etc/letsencrypt/live/lora.fuzziebrain.com/chain.pem
</VirtualHost>
```

## Using the Deployment Script on Other Platforms

To use the deployment script on a different provided, e.g. [DigitalOcean](https://m.do.co/c/6f9b549ca569), create a shell script (e.g. `.env`) that loads the variables into the environment:

```bash
#!/bin/bash
export SS_ORACLE_PASSWORD=
export SS_ORACLE_CHARSET=
export SS_APEX_ADMIN_EMAIL=
export SS_APEX_ADMIN_PASSWORD=
export SS_SERVER_NAME=
export SS_SSL_ENABLED=
export SS_ORACLE_XE_RPM_URL=
export SS_APEX_ZIP_URL=
export SS_ORDS_ZIP_URL=
export SS_POST_DEPLOY_CLEANUP=
```

Enter the required variables, load them, then run the deployment script:

```bash
$ . .env
$ ./deployLora.sh
```