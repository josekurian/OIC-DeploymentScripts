# OIC-DeploymentScripts
**Deployment Scripts for Oracle Integration Cloud**

## Credits
I took the code from the blog post created by Richard Poon

https://blogs.oracle.com/integration/cicd-implementation-for-oic

I couldn't use the scripts as published, and had to fix a substantial amount of bugs in order to make them work.

## Dependencies
1. Git Bash (Windows) | Git (MacOS | Linux | Unix)
1. jq (https://stedolan.github.io/jq/)
1. The scripts and local git repository paths must not have blank spaces (Otherwise jq does not work)

## To-Dos
- [ ]  Add feature for endpoint's tokenization
- [ ]  Review and Standardize log / stdout
- [ ]  Improve logging, remove VERBOSE mode and add shell logger
- [ ]  Include support for Nexus / Artifactory
- [ ]  Add Jenkins pipeline / shared libraries code
- [ ]  Add feature to deactivate selected integrations

## How to use them

**1) Export Integrations > 2) Push to Repository > 3) Pull from Repository > 4) Deploy Integrations**

### Export integrations:
#### _Parameters_
Name                |   Description
------------------- | --------------------------------------------------------------
OIC_ENV             |   (Mandatory) OIC URL
OIC_USER            |   (Mandatory) OIC User
OIC_USER_PWD        |   (Mandatory) OIC User Password
LOCAL_REPOSITORY    |   (Mandatory) Local Repository location (i.e. /scratch/GitHub/mytest1 )
EXPORT_ALL          |   (Mandatory) Option for Exporting all Integrations (true/false)
INTEGRATION_CONFIG  |   (Optional)  Integration Config (config.json) directory

#### _Execution_
_Export Integrations found in the config.json file:_
```
cd /c/Oracle/Code/OIC/OIC-DeploymentScripts/Scripts/01_export_integrations
bash export_integrations.sh https://oic99596029-ocuocictrng26.integration.ocp.oraclecloud.com 99596029-ora034 SuperHardPassword1234 /c/Oracle/Code/OIC/OIC-DeploymentScripts/Artifacts false /c/Oracle/Code/OIC/OIC-DeploymentScripts/Scripts/01_export_integrations/config.json
```

_Export All Integrations:_
```
cd /c/Oracle/Code/OIC/OIC-DeploymentScripts/Scripts/01_export_integrations
bash export_integrations.sh https://oic99596029-ocuocictrng26.integration.ocp.oraclecloud.com 99596029-ora034 SuperHardPassword1234 /c/Oracle/Code/OIC/OIC-DeploymentScripts/Artifacts true
```

### Push to Repository:
#### _Parameters_
Name                |   Description
------------------- | --------------------------------------------------------------
GIT_INSTALL_LOC     |   (Mandatory) Git Install location
LOCAL_REPOSITORY    |   (Mandatory) Local Repo location
BRANCH_NAME         |   (Mandatory) Branch name to push to (i.e. feature/deployments-test)
BITBUCKET_USERNAME  |   (Mandatory) Bitbucket/GitHub Username
BITBUCKET_EMAIL     |   (Mandatory) Bitbucket/GitHub user email
COMMIT_COMMENT      |   (Optional)  Commit description (i.e. "Pushing OIC Integrations to Remote Repo")

#### _Execution_
```
cd /c/Oracle/Code/OIC/OIC-DeploymentScripts/Scripts/02_push_to_repository
bash push_to_repository.sh /c/Users/s.castro.oropeza/AppData/Local/Programs/Git /c/Oracle/Code/OIC/OIC-DeploymentScripts/Artifacts feature/deployments-test scoropeza scoropeza@gmail.com "Pushing OIC Integrations to Remote Repo"
```

### Pull from Repository:

#### _Parameters_
Name                |   Description
------------------- | --------------------------------------------------------------
GIT_INSTALL_LOC     |   (Mandatory) Git Installed location
LOCAL_REPO          |   (Mandatory) Root Local Repo location
REMOTE_REPO         |   (Mandatory) Remote Bitbucket/GitHub Repository
BRANCH_NAME         |   (Mandatory) Remote branch from where to get the Integrations
BITBUCKET_USERNAME  |   (Mandatory) Bitbucket Username
BITBUCKET_EMAIL     |   (Mandatory) Bitbucket user email

#### _Execution_
```
cd /c/Oracle/Code/OIC/OIC-DeploymentScripts/Scripts/03_pull_from_repository
bash pull_from_repository.sh /c/Users/s.castro.oropeza/AppData/Local/Programs/Git /c/Oracle/Code/OIC/Downloads https://github.com/scoropeza/OIC-DeploymentScripts.git feature/deployments-test scoropeza scoropeza@gmail.com
```

### Deploy Integrations

#### _Parameters_
Name                |   Description
------------------- | --------------------------------------------------------------
OIC_ENV             |   (Mandatory) OIC URL
OIC_USER            |   (Mandatory) OIC User
OIC_PASSWORD        |   (Mandatory) OIC User Password
OVERWRITE           |   (Mandatory)  Overwrite flag - If true, it will overwrite Integration if it already exists
IMPORT_ONLY			|	(Mandatory)<br>If true, it will import the integration without the connections and will leave it deactivated.<br>If false, it will import both the integration and the connections and leave it activated.
INTEGRATION_CONFIG	|	(Mandatory) Location of file integrations.json, this file contains the integrations to deploy.
IAR_LOCATION        |   (Mandatory) IAR files location

#### _Execution_
```
cd /c/Oracle/Code/OIC/OIC-DeploymentScripts/Scripts/04_deploy_integrations
bash deploy_integrations.sh https://oic99596029-ocuocictrng26.integration.ocp.oraclecloud.com 99596029-ora034 SuperHardPassword1234 true false /c/Oracle/Code/OIC/OIC-DeploymentScripts/Scripts/04_deploy_integrations/config/integrations.json /c/Oracle/Code/OIC/OIC-DeploymentScripts/Scripts/03_pull_from_repository/IAR_location
```


