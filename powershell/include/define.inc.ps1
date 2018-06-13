<#
   BUT : Contient les constantes utilisées par les différents scripts

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

   ----------
   HISTORIQUE DES VERSIONS
   1.0 - Version de base
#>

$ADMIN_MAIL_ADDRESS="lucien.chaboudez@epfl.ch"


# ---------------------------------------------------------
# Global
$JSON_TEMPLATE_FOLDER = ([IO.Path]::Combine("$PSScriptRoot", "..", "json-templates"))
$DAY2_ACTIONS_FOLDER = ([IO.Path]::Combine("$PSScriptRoot", "..", "2nd-day-actions"))
$JSON_SECRETS_FILE = ([IO.Path]::Combine("$PSScriptRoot", "..", "..", "secrets.json"))

# Environnements
$global:TARGET_ENV_DEV  = 'dev'
$global:TARGET_ENV_TEST = 'test'
$global:TARGET_ENV_PROD = 'prod'

# Pour valider le nom d'environnement passé en paramètre au script principal
$global:TARGET_ENV_LIST = @($global:TARGET_ENV_DEV
					 $global:TARGET_ENV_TEST
					 $global:TARGET_ENV_PROD)

# Nom du tenant par défaut
$global:VRA_TENANT_DEFAULT = "vsphere.local"
$global:VRA_TENANT_EPFL = "EPFL"
$global:VRA_TENANT_ITSERVICES = "ITServices"

# Nom des tenants que l'on devra traiter
$global:TARGET_TENANT_LIST = @($global:VRA_TENANT_EPFL, $global:VRA_TENANT_ITSERVICES<#, $global:VRA_TENANT_DEFAULT #>)

# Adresse mail par défaut à laquelle envoyer les mails de "capacity alert"
$CAPACITY_ALERT_DEFAULT_MAIL = "vsissp-prod-admins@groupes.epfl.ch"


# Information sur les services au sens vRA
$VRA_SERVICE_SUFFIX_PUBLIC=" (Public)"
$VRA_SERVICE_SUFFIX_PRIVATE=" (Private)"

# Nom des custom properties à utiliser.
$VRA_CUSTOM_PROP_EPFL_UNIT_ID = "ch.epfl.unit.id"
$VRA_CUSTOM_PROP_VRA_BG_TYPE = "ch.epfl.vra.bg.type"
$VRA_CUSTOM_PROP_VRA_BG_STATUS = "ch.epfl.vra.bg.status"

# Pour la génération des chaînes de caractères
#$VRA_BG_FAC_ORPHAN_DESC_BASE = "Orphans for faculty {0}"
#$VRA_ENT_DESC_BASE = "Faculty: {0}`nUnit: {1}"

# Types de Business Group possibles
$VRA_BG_TYPE_ADMIN 	 = "admin"
$VRA_BG_TYPE_SERVICE = "service"
$VRA_BG_TYPE_UNIT 	 = "unit"

# Status de Business Group possibles
$VRA_BG_STATUS_ALIVE = "alive"
$VRA_BG_STATUS_GHOST = "ghost"



