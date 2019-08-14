<#
    BUT : Contient les informations nécessaire pour s'interfacer avec l'environnement de backup NetBackpu

    DEPENDANCES : Ce script a besoin de "define.inc.ps1" pour fonctionner correctement

    AUTEUR : Lucien Chaboudez
    DATE   : Juin 2019

    ----------
    HISTORIQUE DES VERSIONS
    1.0 - Version de base
#>

# ===================================================================================
# =================================== Backup ========================================
# ===================================================================================
# Serveurs de backup en fonction de l'environnement
$global:XAAS_BACKUP_SERVER_LIST = @{}
$global:XAAS_BACKUP_SERVER_LIST[$global:TARGET_ENV__DEV]  = ""
$global:XAAS_BACKUP_SERVER_LIST[$global:TARGET_ENV__TEST] = ""
$global:XAAS_BACKUP_SERVER_LIST[$global:TARGET_ENV__PROD] = ""


# ------------------------------------------------
# Utilisateurs par environnement
# Les noms d'utilisateur NE DOIVENT PAS avoir le nom du domaine (ex: username@domain.com)
$global:XAAS_BACKUP_USER_LIST = @{}
$global:XAAS_BACKUP_USER_LIST[$global:TARGET_ENV__DEV]	 = ""
$global:XAAS_BACKUP_USER_LIST[$global:TARGET_ENV__TEST]	 = ""
$global:XAAS_BACKUP_USER_LIST[$global:TARGET_ENV__PROD]  = ""


# ------------------------------------------------
# Mot de passe
# Définis par environnement
$global:XAAS_BACKUP_PASSWORD_LIST = @{}
$global:XAAS_BACKUP_PASSWORD_LIST[$global:TARGET_ENV__DEV]	 = ""
$global:XAAS_BACKUP_PASSWORD_LIST[$global:TARGET_ENV__TEST]  = ""
$global:XAAS_BACKUP_PASSWORD_LIST[$global:TARGET_ENV__PROD]  = ""



# ===================================================================================
# ============================== vCenter / vSphere ==================================
# ===================================================================================
# Serveurs vCenter en fonction de l'environnement
$global:XAAS_BACKUP_VCENTER_SERVER_LIST = @{}
$global:XAAS_BACKUP_VCENTER_SERVER_LIST[$global:TARGET_ENV__DEV]  = ""
$global:XAAS_BACKUP_VCENTER_SERVER_LIST[$global:TARGET_ENV__TEST] = ""
$global:XAAS_BACKUP_VCENTER_SERVER_LIST[$global:TARGET_ENV__PROD] = ""


# ------------------------------------------------
# Utilisateurs par environnement
# Les noms d'utilisateur NE DOIVENT PAS avoir le nom du domaine (ex: username@domain.com)
$global:XAAS_BACKUP_VCENTER_USER_LIST = @{}
$global:XAAS_BACKUP_VCENTER_USER_LIST[$global:TARGET_ENV__DEV]	 = ""
$global:XAAS_BACKUP_VCENTER_USER_LIST[$global:TARGET_ENV__TEST]  = ""
$global:XAAS_BACKUP_VCENTER_USER_LIST[$global:TARGET_ENV__PROD]  = ""


# ------------------------------------------------
# Mot de passe
# Définis par environnement
$global:XAAS_BACKUP_VCENTER_PASSWORD_LIST = @{}
$global:XAAS_BACKUP_VCENTER_PASSWORD_LIST[$global:TARGET_ENV__DEV]	 = ""
$global:XAAS_BACKUP_VCENTER_PASSWORD_LIST[$global:TARGET_ENV__TEST]	 = ""
$global:XAAS_BACKUP_VCENTER_PASSWORD_LIST[$global:TARGET_ENV__PROD]  = ""